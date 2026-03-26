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
