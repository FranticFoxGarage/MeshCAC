#!/bin/bash
# MeshCAC - Home Assistant state monitor
# Watches screensaver DBus signal for ALL lock/unlock events (including password)
# Runs as a systemd user service

CONFIG="/etc/meshcac/meshcac.conf"

if [ ! -f "$CONFIG" ]; then
    logger -t "meshcac" "ERROR: Config file not found at $CONFIG"
    exit 1
fi

source "$CONFIG"

LOG_TAG="meshcac"

# Exit cleanly if HA not configured
if [ -z "$HA_TOKEN" ]; then
    logger -t "$LOG_TAG" "HA monitor: no token set, exiting"
    exit 0
fi

send_ha_state() {
    local state="$1"
    local resolve_opt=""
    [ -n "$HA_IP" ] && resolve_opt="--resolve ${HA_HOST}:443:${HA_IP}"
    /usr/bin/curl -sf $resolve_opt -X POST "https://$HA_HOST/api/states/$HA_ENTITY" \
      -H "Authorization: Bearer $HA_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"state\": \"$state\", \"attributes\": {\"friendly_name\": \"$HA_FRIENDLY\", \"device_class\": \"lock\"}}" >/dev/null 2>&1 \
      || logger -t "$LOG_TAG" "ERROR: Failed to update HA state to $state"
}

get_dbus_signal() {
    case "$DESKTOP_ENV" in
        cinnamon|xfce) echo "type='signal',interface='org.cinnamon.ScreenSaver',member='ActiveChanged'" ;;
        gnome)         echo "type='signal',interface='org.gnome.ScreenSaver',member='ActiveChanged'" ;;
        kde)           echo "type='signal',interface='org.kde.screensaver',member='ActiveChanged'" ;;
        *)
            logger -t "$LOG_TAG" "HA monitor: unknown DESKTOP_ENV, defaulting to cinnamon signal"
            echo "type='signal',interface='org.cinnamon.ScreenSaver',member='ActiveChanged'"
            ;;
    esac
}

logger -t "$LOG_TAG" "HA monitor started (DE: $DESKTOP_ENV)"

# Get DBus session from the user's running DE process
case "$DESKTOP_ENV" in
    cinnamon) DE_PROC="cinnamon" ;;
    gnome)    DE_PROC="gnome-shell" ;;
    kde)      DE_PROC="plasmashell" ;;
    xfce)     DE_PROC="xfce4-session" ;;
    *)        DE_PROC="cinnamon" ;;
esac

# Wait up to 30s for the DE process to be available (handles early service start)
ELAPSED=0
while [ $ELAPSED -lt 30 ]; do
    DE_PID=$(pgrep -u "$USERNAME" -x "$DE_PROC" | head -1)
    [ -n "$DE_PID" ] && break
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

if [ -z "$DE_PID" ]; then
    logger -t "$LOG_TAG" "ERROR: HA monitor could not find $DE_PROC process, exiting"
    exit 1
fi

export DBUS_SESSION_BUS_ADDRESS=$(tr '\0' '\n' < /proc/$DE_PID/environ 2>/dev/null | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)
export DISPLAY=$(tr '\0' '\n' < /proc/$DE_PID/environ 2>/dev/null | grep ^DISPLAY= | cut -d= -f2-)

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    logger -t "$LOG_TAG" "ERROR: HA monitor could not get DBUS_SESSION_BUS_ADDRESS, exiting"
    exit 1
fi

logger -t "$LOG_TAG" "HA monitor connected to DBus"

dbus-monitor --session "$(get_dbus_signal)" 2>/dev/null | \
while read -r line; do
    case "$line" in
        *"boolean true"*)
            logger -t "$LOG_TAG" "Screen locked - updating HA"
            send_ha_state "off"
            ;;
        *"boolean false"*)
            logger -t "$LOG_TAG" "Screen unlocked - updating HA"
            send_ha_state "on"
            ;;
    esac
done
