#!/bin/bash
# change-apn-auto.sh
#
# Auto-detects ALL cellular modem interfaces on the box (any combo/count of
# USB800 / USB730L) and reads or changes their APN. No need to know ahead of
# time which dongles are plugged in, how many, or which interface maps to
# which physical modem.
#
# Handles multiple modems sharing the same default gateway (e.g. two
# USB730Ls both at 192.168.2.1) by scoping each modem's traffic to its own
# interface with per-interface policy routing, so probes/reads/writes never
# cross-talk to the wrong dongle.
#
# Usage:
#   ./change-apn-auto.sh                          # read-only: show current APN on all modems
#   ./change-apn-auto.sh <new_apn>                # apply <new_apn> to ALL detected modems
#                                                  # (refuses if it finds more than one model —
#                                                  # AT&T and Verizon APNs are never the same string)
#   ./change-apn-auto.sh --usb800=<apn> --usb730l=<apn>
#                                                  # apply a different APN per model — required
#                                                  # for boxes with one of each

set -u

ROUTE_TABLE_BASE=200

# --- Argument handling ---
BLANKET_APN=""
APN_USB800=""
APN_USB730L=""

for arg in "$@"; do
    case "$arg" in
        --usb800=*)  APN_USB800="${arg#--usb800=}" ;;
        --usb730l=*) APN_USB730L="${arg#--usb730l=}" ;;
        *)           BLANKET_APN="$arg" ;;
    esac
done

IFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^eth[1-9]$')

if [ -z "$IFACES" ]; then
    echo "No candidate modem interfaces found (eth1+)."
    exit 1
fi

# --- Pass 1: detect what's actually plugged in (read-only, no writes) ---
DETECTED_IFACES=()
DETECTED_MODELS=()
DETECTED_IPS=()
DETECTED_GATEWAYS=()
DISTINCT_MODELS=()

idx=0
for IFACE in $IFACES; do
    idx=$((idx + 1))
    TABLE=$((ROUTE_TABLE_BASE + idx))

    LOCAL_IP=$(ip -4 addr show dev "$IFACE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    if [ -z "$LOCAL_IP" ]; then
        continue  # interface has no IP, not an active modem
    fi

    DYN_GATEWAY=$(ip route show dev "$IFACE" 2>/dev/null | grep default | awk '{print $3}')
    GATEWAY="${DYN_GATEWAY:-192.168.2.1}"

    ip route add "$GATEWAY"/32 dev "$IFACE" table "$TABLE" 2>/dev/null
    ip rule add from "$LOCAL_IP" table "$TABLE" priority "$TABLE" 2>/dev/null

    PROBE_FILE="/tmp/apn_probe_${IFACE}.html"

    wget -q -T 8 -O "$PROBE_FILE" --bind-address="$LOCAL_IP" \
        --header="Host: att.manager" "http://$GATEWAY/networks/" 2>/dev/null

    if grep -q "NetworksProfileAPN" "$PROBE_FILE" 2>/dev/null; then
        MODEL="usb800"
    else
        wget -q -T 8 -O "$PROBE_FILE" --bind-address="$LOCAL_IP" \
            "http://$GATEWAY/networks/" 2>/dev/null
        if grep -q "NetworksFourGLTEAPN" "$PROBE_FILE" 2>/dev/null; then
            MODEL="usb730l"
        else
            MODEL="unknown"
        fi
    fi

    ip rule del from "$LOCAL_IP" table "$TABLE" priority "$TABLE" 2>/dev/null
    ip route del "$GATEWAY"/32 dev "$IFACE" table "$TABLE" 2>/dev/null

    echo "$IFACE ($LOCAL_IP) -> gateway $GATEWAY -> detected: $MODEL"

    if [ "$MODEL" = "unknown" ]; then
        continue
    fi

    DETECTED_IFACES+=("$IFACE")
    DETECTED_MODELS+=("$MODEL")
    DETECTED_IPS+=("$LOCAL_IP")
    DETECTED_GATEWAYS+=("$GATEWAY")

    if [[ ! " ${DISTINCT_MODELS[*]:-} " == *" $MODEL "* ]]; then
        DISTINCT_MODELS+=("$MODEL")
    fi
done
echo

if [ "${#DETECTED_IFACES[@]}" -eq 0 ]; then
    echo "No modems could be identified. Nothing to do."
    exit 1
fi

# --- Safety check: refuse a blanket APN across mixed carrier models ---
if [ -n "$BLANKET_APN" ] && [ "${#DISTINCT_MODELS[@]}" -gt 1 ]; then
    echo "ERROR: This box has more than one modem model (${DISTINCT_MODELS[*]})."
    echo "A single APN can't be safely applied to both — AT&T and Verizon APNs differ."
    echo "Use per-model flags instead, e.g.:"
    echo "  $0 --usb800=broadband --usb730l=vzwinternet"
    exit 1
fi

# --- Pass 2: read current APN on each modem, and apply a change if one was given for its model ---
for i in "${!DETECTED_IFACES[@]}"; do
    IFACE="${DETECTED_IFACES[$i]}"
    MODEL="${DETECTED_MODELS[$i]}"
    LOCAL_IP="${DETECTED_IPS[$i]}"
    GATEWAY="${DETECTED_GATEWAYS[$i]}"
    TABLE=$((ROUTE_TABLE_BASE + i + 1))
    BASE_URL="http://$GATEWAY"
    COOKIE_JAR="/tmp/apn_cookies_${IFACE}.txt"
    PAGE_FILE="/tmp/apn_${IFACE}.html"

    if [ "$MODEL" = "usb800" ]; then
        HOST_HEADER="att.manager"
        FIELD="NetworksProfileAPN"
        NEW_APN="${BLANKET_APN:-$APN_USB800}"
    else
        HOST_HEADER=""
        FIELD="NetworksFourGLTEAPN"
        NEW_APN="${BLANKET_APN:-$APN_USB730L}"
    fi

    echo "=== $IFACE ($MODEL, $LOCAL_IP) -> gateway $GATEWAY ==="

    ip route add "$GATEWAY"/32 dev "$IFACE" table "$TABLE" 2>/dev/null
    ip rule add from "$LOCAL_IP" table "$TABLE" priority "$TABLE" 2>/dev/null

    HOST_ARGS=()
    if [ -n "$HOST_HEADER" ]; then
        HOST_ARGS=(--header="Host: $HOST_HEADER")
    fi

    wget -q -T 8 -O "$PAGE_FILE" --save-cookies "$COOKIE_JAR" --keep-session-cookies \
        --bind-address="$LOCAL_IP" "${HOST_ARGS[@]}" "$BASE_URL/networks/"

    TOKEN=$(grep -oP "name=\"gSecureToken\".*?value=\"\K[^\"]+" "$PAGE_FILE" | head -1)
    CURRENT_APN=$(grep -oP "name=\"$FIELD\".*?value=\"\K[^\"]*" "$PAGE_FILE" | head -1)

    if [ -z "$TOKEN" ]; then
        echo "ERROR: Couldn't extract security token on $IFACE. Admin page may be unreachable or layout changed."
        ip rule del from "$LOCAL_IP" table "$TABLE" priority "$TABLE" 2>/dev/null
        ip route del "$GATEWAY"/32 dev "$IFACE" table "$TABLE" 2>/dev/null
        echo
        continue
    fi

    echo "Current APN: $CURRENT_APN"

    if [ -n "$NEW_APN" ]; then
        echo "Setting APN to: $NEW_APN"

        if [ "$MODEL" = "usb800" ]; then
            RESPONSE=$(wget -q -T 8 -O - --load-cookies "$COOKIE_JAR" --bind-address="$LOCAL_IP" \
                "${HOST_ARGS[@]}" --header="Referer: http://$HOST_HEADER/networks/" \
                --post-data="${FIELD}=${NEW_APN}&NetworksProfileAuthentication=0&NetworksProfileUsername=&NetworksProfilePassword=&gSecureToken=${TOKEN}" \
                "$BASE_URL/networks/")
            if echo "$RESPONSE" | grep -q "saved successfully"; then
                echo "SUCCESS: Changes saved on $IFACE."
            else
                echo "WARNING: No success confirmation seen on $IFACE. Verify manually."
            fi
        else
            echo "Disconnecting active session before write ($IFACE)..."
            wget -q -T 8 -O /dev/null --load-cookies "$COOKIE_JAR" --bind-address="$LOCAL_IP" \
                "$BASE_URL/srv/disconnect"
            sleep 3

            wget -q -T 8 -O - --load-cookies "$COOKIE_JAR" --bind-address="$LOCAL_IP" \
                --header="Referer: $BASE_URL/networks/" \
                --post-data="NetworksConnectionPreference=0&NetworksPreferredTechnology=31&${FIELD}=${NEW_APN}&NetworksOtherAPN=&gSecureToken=${TOKEN}" \
                "$BASE_URL/networks/" > "$PAGE_FILE"

            echo "Reconnecting ($IFACE)..."
            wget -q -T 8 -O /dev/null --load-cookies "$COOKIE_JAR" --bind-address="$LOCAL_IP" \
                "$BASE_URL/srv/connect"
            sleep 3

            wget -q -T 8 -O "$PAGE_FILE" --save-cookies "$COOKIE_JAR" --keep-session-cookies \
                --bind-address="$LOCAL_IP" "$BASE_URL/networks/"
            APPLIED_APN=$(grep -oP "name=\"$FIELD\".*?value=\"\K[^\"]*" "$PAGE_FILE" | head -1)

            if [ "$APPLIED_APN" = "$NEW_APN" ]; then
                echo "SUCCESS: APN on $IFACE now shows as '$APPLIED_APN'."
            else
                echo "WARNING: $IFACE shows APN as '$APPLIED_APN', expected '$NEW_APN'. Verify manually."
            fi
        fi
    fi

    ip rule del from "$LOCAL_IP" table "$TABLE" priority "$TABLE" 2>/dev/null
    ip route del "$GATEWAY"/32 dev "$IFACE" table "$TABLE" 2>/dev/null
    echo
done
