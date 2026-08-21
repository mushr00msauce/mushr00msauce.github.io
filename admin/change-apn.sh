#!/bin/bash
# change-apn.sh - Remotely read or change the APN on the Mushbox's USB800 or USB730L modem
# Usage:
#   ./change-apn.sh usb800  [new-apn]     # AT&T/FirstNet modem on eth1
#   ./change-apn.sh usb730l [new-apn]     # Verizon modem on eth2
# If new-apn is omitted, just prints the current APN without changing anything.

set -e

MODEM="$1"
NEW_APN="$2"

if [ -z "$MODEM" ]; then
    echo "Usage: $0 <usb800|usb730l> [new-apn]"
    exit 1
fi

case "$MODEM" in
    usb800)
        IFACE="eth1"
        GATEWAY=$(ip route show dev "$IFACE" 2>/dev/null | grep default | awk '{print $3}')
        LOCAL_IP=$(ip route show dev "$IFACE" 2>/dev/null | grep "src" | awk '{print $NF}')
        if [ -z "$GATEWAY" ] || [ -z "$LOCAL_IP" ]; then
            echo "ERROR: Couldn't determine gateway/local IP for $IFACE. Is the modem attached to the network right now?"
            exit 1
        fi
        HOST_HEADER="att.manager"
        BASE_URL="http://$GATEWAY"
        FIELD="NetworksProfileAPN"
        COOKIE_JAR="/tmp/apn_cookies_usb800.txt"
        PAGE_FILE="/tmp/apn_usb800.html"
        ;;
    usb730l)
        IFACE="eth2"
        LOCAL_IP=$(ip -4 addr show "$IFACE" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)
        if [ -z "$LOCAL_IP" ]; then
            echo "ERROR: Couldn't determine local IP for $IFACE. Is the modem attached to the network right now?"
            exit 1
        fi
        GATEWAY="192.168.2.1"
        HOST_HEADER=""
        BASE_URL="http://$GATEWAY"
        FIELD="NetworksFourGLTEAPN"
        COOKIE_JAR="/tmp/apn_cookies_usb730l.txt"
        PAGE_FILE="/tmp/apn_usb730l.html"
        ;;
    *)
        echo "ERROR: Unknown modem '$MODEM'. Use 'usb800' or 'usb730l'."
        exit 1
        ;;
esac

echo "Modem:    $MODEM"
echo "Iface:    $IFACE"
echo "Local IP: $LOCAL_IP"
echo "Gateway:  $GATEWAY"
echo ""

HOST_ARGS=()
if [ -n "$HOST_HEADER" ]; then
    HOST_ARGS=(--header="Host: $HOST_HEADER")
fi

wget -q -T 8 -O "$PAGE_FILE" --save-cookies "$COOKIE_JAR" --keep-session-cookies \
    --bind-address="$LOCAL_IP" "${HOST_ARGS[@]}" "$BASE_URL/networks/"

TOKEN=$(grep -oP "name=\"gSecureToken\".*?value=\"\K[^\"]+" "$PAGE_FILE" | head -1)
CURRENT_APN=$(grep -oP "name=\"$FIELD\".*?value=\"\K[^\"]*" "$PAGE_FILE" | head -1)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Couldn't extract security token. The modem's admin page may be unreachable or its layout changed."
    exit 1
fi

echo "Current APN: $CURRENT_APN"

if [ -z "$NEW_APN" ]; then
    echo "(No new APN given - nothing changed. Pass a value as the 2nd argument to set one.)"
    exit 0
fi

echo "Setting APN to: $NEW_APN"
echo ""

if [ "$MODEM" = "usb800" ]; then
    RESPONSE=$(wget -q -T 8 -O - --load-cookies "$COOKIE_JAR" --bind-address="$LOCAL_IP" \
        --header="Host: $HOST_HEADER" --header="Referer: http://$HOST_HEADER/networks/" \
        --post-data="${FIELD}=${NEW_APN}&NetworksProfileAuthentication=0&NetworksProfileUsername=&NetworksProfilePassword=&gSecureToken=${TOKEN}" \
        "$BASE_URL/networks/")
    if echo "$RESPONSE" | grep -q "saved successfully"; then
        echo "SUCCESS: Changes saved."
    else
        echo "WARNING: No success confirmation seen in response. Verify manually."
    fi
else
    echo "Disconnecting active session before write..."
    wget -q -T 8 -O /dev/null --load-cookies "$COOKIE_JAR" --bind-address="$LOCAL_IP" \
        "$BASE_URL/srv/disconnect"
    sleep 3

    RESPONSE=$(wget -q -T 8 -O - --load-cookies "$COOKIE_JAR" --bind-address="$LOCAL_IP" \
        --header="Referer: $BASE_URL/networks/" \
        --post-data="NetworksConnectionPreference=0&NetworksPreferredTechnology=31&${FIELD}=${NEW_APN}&NetworksOtherAPN=&gSecureToken=${TOKEN}" \
        "$BASE_URL/networks/")
    echo "$RESPONSE" > "$PAGE_FILE"

    echo "Reconnecting..."
    wget -q -T 8 -O /dev/null --load-cookies "$COOKIE_JAR" --bind-address="$LOCAL_IP" \
        "$BASE_URL/srv/connect"
    sleep 3

    # Re-fetch fresh page to verify actual persisted state (not just the echoed POST response)
    wget -q -T 8 -O "$PAGE_FILE" --save-cookies "$COOKIE_JAR" --keep-session-cookies \
        --bind-address="$LOCAL_IP" "$BASE_URL/networks/"
    APPLIED_APN=$(grep -oP "name=\"$FIELD\".*?value=\"\K[^\"]*" "$PAGE_FILE" | head -1)

    if [ "$APPLIED_APN" = "$NEW_APN" ]; then
        echo "SUCCESS: APN now shows as '$APPLIED_APN'."
    else
        echo "WARNING: Page shows APN as '$APPLIED_APN', expected '$NEW_APN'. Verify manually."
    fi
fi
