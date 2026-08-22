#!/bin/bash
# change-apn-auto.sh
#
# Auto-detects ALL cellular modem interfaces on the box (any combo/count of
# USB800 / USB730L, including USB730L units running in IP Passthrough mode)
# and reads or changes their APN. No need to know ahead of time which
# dongles are plugged in, how many, or which interface maps to which
# physical modem.
#
# Requires sudo/root — the per-interface policy routing below (ip route/ip
# rule) needs it, and on some boxes the routes wget needs to actually reach
# the modem's admin page live in a per-interface named table rather than the
# main table, which also needs root to read reliably. Run as:
#   sudo ./change-apn-auto.sh ...
#
# --- Three known modem/gateway patterns (found the hard way — see below) ---
#   1. USB800 (AT&T/FirstNet):
#        gateway = dynamic, discovered from that interface's own default
#                  route (may live in a per-interface named routing table,
#                  e.g. `table eth1`, not just the main table — the original
#                  version of this script only checked the main table and
#                  silently fell back to the wrong gateway as a result)
#        Host header = att.manager
#        APN field    = NetworksProfileAPN
#   2. USB730L, standard mode:
#        gateway = fixed 192.168.2.1
#        Host header = none
#        APN field    = NetworksFourGLTEAPN
#   3. USB730L, IP Passthrough mode (confirmed on a real unit 2026-08-21/22):
#        The admin page itself says "IP Passthrough is always used. The
#        network IP address is assigned to your computer, not to your
#        USB730L." In this mode the modem does NOT sit behind the usual
#        fixed 192.168.2.1 address — it gets its own dynamic carrier-side
#        gateway (same as a USB800 would). Hitting that gateway on port 80
#        with no Host header returns a 307 redirect to http://my.usb, and
#        following that redirect blindly loops forever (my.usb resolves to
#        a link-local-ish address that isn't reachable the way the redirect
#        implies). The actual fix is to send the Host header it's asking
#        for up front:
#        gateway = dynamic, same lookup as USB800
#        Host header = my.usb
#        APN field    = NetworksFourGLTEAPN (same field name as standard 730L)
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
DETECTED_HOST_HEADERS=()
DETECTED_FIELDS=()
DISTINCT_MODELS=()

idx=0
for IFACE in $IFACES; do
    idx=$((idx + 1))
    TABLE=$((ROUTE_TABLE_BASE + idx))

    LOCAL_IP=$(ip -4 addr show dev "$IFACE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    if [ -z "$LOCAL_IP" ]; then
        continue  # interface has no IP, not an active modem
    fi

    # Dynamic gateway can live in the main table OR a per-interface named
    # table (e.g. `default via X dev eth1 table eth1`) — check every table,
    # not just the main one, or this silently falls back to the wrong
    # gateway for any interface whose default route isn't in the main table.
    DYN_GATEWAY=$(ip route show table all 2>/dev/null | \
        awk -v ifc="$IFACE" '$1=="default" && $2=="via" { for(i=1;i<=NF;i++) if($i=="dev" && $(i+1)==ifc) { print $3; exit } }')
    GATEWAY="${DYN_GATEWAY:-192.168.2.1}"

    ip route add "$GATEWAY"/32 dev "$IFACE" table "$TABLE" 2>/dev/null
    ip rule add from "$LOCAL_IP" table "$TABLE" priority "$TABLE" 2>/dev/null

    PROBE_FILE="/tmp/apn_probe_${IFACE}.html"
    PROBE_COOKIE_JAR="/tmp/apn_cookies_${IFACE}.txt"

    MODEL="unknown"
    HOST_HEADER=""
    FIELD=""

    # --- Combo 1: USB800 — dynamic gateway, Host: att.manager ---
    wget -q -T 8 --max-redirect=0 -O "$PROBE_FILE" --save-cookies "$PROBE_COOKIE_JAR" --keep-session-cookies \
        --bind-address="$LOCAL_IP" --header="Host: att.manager" "http://$GATEWAY/networks/" 2>/dev/null
    if grep -q "NetworksProfileAPN" "$PROBE_FILE" 2>/dev/null; then
        MODEL="usb800"; HOST_HEADER="att.manager"; FIELD="NetworksProfileAPN"
    fi

    # --- Combo 2: USB730L, IP Passthrough mode — dynamic gateway, Host: my.usb ---
    if [ "$MODEL" = "unknown" ]; then
        wget -q -T 8 --max-redirect=0 -O "$PROBE_FILE" --save-cookies "$PROBE_COOKIE_JAR" --keep-session-cookies \
            --bind-address="$LOCAL_IP" --header="Host: my.usb" "http://$GATEWAY/networks/" 2>/dev/null
        if grep -q "NetworksFourGLTEAPN" "$PROBE_FILE" 2>/dev/null; then
            MODEL="usb730l"; HOST_HEADER="my.usb"; FIELD="NetworksFourGLTEAPN"
        fi
    fi

    # --- Combo 3: USB730L, standard mode — fixed gateway 192.168.2.1, no Host header ---
    if [ "$MODEL" = "unknown" ]; then
        wget -q -T 8 --max-redirect=0 -O "$PROBE_FILE" --save-cookies "$PROBE_COOKIE_JAR" --keep-session-cookies \
            --bind-address="$LOCAL_IP" "http://$GATEWAY/networks/" 2>/dev/null
        if grep -q "NetworksFourGLTEAPN" "$PROBE_FILE" 2>/dev/null; then
            MODEL="usb730l"; HOST_HEADER=""; FIELD="NetworksFourGLTEAPN"
        fi
    fi

    ip rule del from "$LOCAL_IP" table "$TABLE" priority "$TABLE" 2>/dev/null
    ip route del "$GATEWAY"/32 dev "$IFACE" table "$TABLE" 2>/dev/null

    echo "$IFACE ($LOCAL_IP) -> gateway $GATEWAY -> detected: $MODEL${HOST_HEADER:+ (Host: $HOST_HEADER)}"

    if [ "$MODEL" = "unknown" ]; then
        continue
    fi

    DETECTED_IFACES+=("$IFACE")
    DETECTED_MODELS+=("$MODEL")
    DETECTED_IPS+=("$LOCAL_IP")
    DETECTED_GATEWAYS+=("$GATEWAY")
    DETECTED_HOST_HEADERS+=("$HOST_HEADER")
    DETECTED_FIELDS+=("$FIELD")

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
    HOST_HEADER="${DETECTED_HOST_HEADERS[$i]}"
    FIELD="${DETECTED_FIELDS[$i]}"
    TABLE=$((ROUTE_TABLE_BASE + i + 1))
    BASE_URL="http://$GATEWAY"
    COOKIE_JAR="/tmp/apn_cookies_${IFACE}.txt"
    PAGE_FILE="/tmp/apn_${IFACE}.html"

    if [ "$MODEL" = "usb800" ]; then
        NEW_APN="${BLANKET_APN:-$APN_USB800}"
    else
        NEW_APN="${BLANKET_APN:-$APN_USB730L}"
    fi

    echo "=== $IFACE ($MODEL, $LOCAL_IP) -> gateway $GATEWAY${HOST_HEADER:+ (Host: $HOST_HEADER)} ==="

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
                "${HOST_ARGS[@]}" --header="Referer: http://${HOST_HEADER:-$GATEWAY}/networks/" \
                --post-data="${FIELD}=${NEW_APN}&NetworksProfileAuthentication=0&NetworksProfileUsername=&NetworksProfilePassword=&gSecureToken=${TOKEN}" \
                "$BASE_URL/networks/")
            if echo "$RESPONSE" | grep -q "saved successfully"; then
                echo "SUCCESS: Changes saved on $IFACE."
            else
                echo "WARNING: No success confirmation seen on $IFACE. Verify manually."
            fi
        else
            # Covers both USB730L variants (standard fixed-gateway and IP
            # Passthrough dynamic-gateway) — same disconnect/write/reconnect
            # dance either way, just with HOST_ARGS applied when the
            # passthrough variant's Host header is set (empty for standard).
            echo "Disconnecting active session before write ($IFACE)..."
            wget -q -T 8 -O /dev/null --load-cookies "$COOKIE_JAR" --bind-address="$LOCAL_IP" \
                "${HOST_ARGS[@]}" "$BASE_URL/srv/disconnect"
            sleep 3

            wget -q -T 8 -O - --load-cookies "$COOKIE_JAR" --bind-address="$LOCAL_IP" \
                "${HOST_ARGS[@]}" --header="Referer: $BASE_URL/networks/" \
                --post-data="NetworksConnectionPreference=0&NetworksPreferredTechnology=31&${FIELD}=${NEW_APN}&NetworksOtherAPN=&gSecureToken=${TOKEN}" \
                "$BASE_URL/networks/" > "$PAGE_FILE"

            echo "Reconnecting ($IFACE)..."
            wget -q -T 8 -O /dev/null --load-cookies "$COOKIE_JAR" --bind-address="$LOCAL_IP" \
                "${HOST_ARGS[@]}" "$BASE_URL/srv/connect"
            sleep 3

            wget -q -T 8 -O "$PAGE_FILE" --save-cookies "$COOKIE_JAR" --keep-session-cookies \
                --bind-address="$LOCAL_IP" "${HOST_ARGS[@]}" "$BASE_URL/networks/"
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
