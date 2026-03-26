#!/bin/bash
# MeshCAC - USB unlock/lock script
# Called by udev on device connect/disconnect

CONFIG="/etc/meshcac/meshcac.conf"

if [ ! -f "$CONFIG" ]; then
    logger -t "meshcac" "ERROR: Config file not found at $CONFIG"
    exit 1
fi

source "$CONFIG"

LOG_TAG="meshcac"
ACTION="$1"

log_msg() {
    logger -t "$LOG_TAG" "$1"
}

get_user_env() {
    local process
    case "$DESKTOP_ENV" in
        cinnamon)  process="cinnamon" ;;
        gnome)     process="gnome-shell" ;;
        kde)       process="plasmashell" ;;
        xfce)      process="xfce4-session" ;;
        hyprland)  process="Hyprland" ;;
        *)
            log_msg "ERROR: Unknown DESKTOP_ENV '$DESKTOP_ENV'"
            return 1
            ;;
    esac

    local pid
    pid=$(pgrep -u "$USERNAME" -x "$process" | head -1)
    if [ -z "$pid" ]; then
        log_msg "ERROR: Could not find $process process for $USERNAME"
        return 1
    fi

    export DBUS_SESSION_BUS_ADDRESS=$(tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)
    export DISPLAY=$(tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep ^DISPLAY= | cut -d= -f2-)

    if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
        log_msg "ERROR: Could not get DBUS_SESSION_BUS_ADDRESS"
        return 1
    fi
    return 0
}

run_as_user() {
    su "$USERNAME" -c "DISPLAY=$DISPLAY DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS $1" 2>/dev/null
}

send_ha_state() {
    [ -z "$HA_TOKEN" ] && return 0
    local state="$1"
    local resolve_opt=""
    [ -n "$HA_IP" ] && resolve_opt="--resolve ${HA_HOST}:443:${HA_IP}"
    local tmpscript
    tmpscript=$(mktemp /tmp/meshcac-ha.XXXXXX.sh)
    cat > "$tmpscript" <<EOF
#!/bin/bash
if ! /usr/bin/curl -sf $resolve_opt -X POST "https://$HA_HOST/api/states/$HA_ENTITY" \
  -H "Authorization: Bearer $HA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"state": "$state", "attributes": {"friendly_name": "$HA_FRIENDLY", "device_class": "lock"}}' >/dev/null 2>&1; then
    logger -t meshcac "ERROR: Failed to update HA state to $state"
fi
rm -f "\$0"
EOF
    chmod +x "$tmpscript"
    systemd-run --quiet --no-block /bin/bash "$tmpscript"
}

ensure_screensaver_daemon() {
    if ! pgrep -u "$USERNAME" -f cinnamon-screensaver &>/dev/null; then
        log_msg "cinnamon-screensaver not running - starting it"
        run_as_user "cinnamon-screensaver &"
        sleep 1
    fi
}

do_screensaver_disable() {
    case "$DESKTOP_ENV" in
        cinnamon)
            ensure_screensaver_daemon
            run_as_user "cinnamon-screensaver-command -d"
            run_as_user "dbus-send --session --dest=org.cinnamon.SettingsDaemon.Power --print-reply /org/cinnamon/SettingsDaemon/Power org.freedesktop.DBus.Properties.Set string:'org.cinnamon.SettingsDaemon.Power' string:'IdleActivationEnabled' variant:boolean:false"
            run_as_user "gsettings set org.cinnamon.desktop.screensaver lock-enabled false"
            run_as_user "gsettings set org.cinnamon.desktop.session idle-delay uint32 0"
            ;;
        gnome)
            run_as_user "dbus-send --session --type=method_call --dest=org.gnome.ScreenSaver /org/gnome/ScreenSaver org.gnome.ScreenSaver.SetActive boolean:false"
            run_as_user "gsettings set org.gnome.desktop.screensaver lock-enabled false"
            run_as_user "gsettings set org.gnome.desktop.session idle-delay uint32 0"
            ;;
        kde)
            run_as_user "qdbus org.kde.screensaver /ScreenSaver SimulateUserActivity"
            run_as_user "kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock false"
            ;;
        xfce)
            run_as_user "xfconf-query -c xfce4-screensaver -p /saver/enabled -s false"
            run_as_user "xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -s false"
            ;;
        hyprland)
            # Kill hypridle to prevent idle locking while device is connected
            pkill -u "$USERNAME" -x hypridle 2>/dev/null || true
            # Unlock hyprlock if it's running (SIGUSR1 is hyprlock's unlock signal)
            pkill -u "$USERNAME" -USR1 hyprlock 2>/dev/null || true
            ;;
    esac
}

do_screensaver_enable() {
    case "$DESKTOP_ENV" in
        cinnamon)
            ensure_screensaver_daemon
            run_as_user "gsettings set org.cinnamon.desktop.screensaver lock-enabled true"
            run_as_user "gsettings set org.cinnamon.desktop.session idle-delay uint32 $IDLE_LOCK_DELAY"
            run_as_user "dbus-send --session --dest=org.cinnamon.SettingsDaemon.Power --print-reply /org/cinnamon/SettingsDaemon/Power org.freedesktop.DBus.Properties.Set string:'org.cinnamon.SettingsDaemon.Power' string:'IdleActivationEnabled' variant:boolean:true"
            run_as_user "cinnamon-screensaver-command -l"
            ;;
        gnome)
            run_as_user "gsettings set org.gnome.desktop.screensaver lock-enabled true"
            run_as_user "gsettings set org.gnome.desktop.session idle-delay uint32 $IDLE_LOCK_DELAY"
            run_as_user "dbus-send --session --type=method_call --dest=org.gnome.ScreenSaver /org/gnome/ScreenSaver org.gnome.ScreenSaver.SetActive boolean:true"
            ;;
        kde)
            run_as_user "kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock true"
            run_as_user "kwriteconfig5 --file kscreenlockerrc --group Daemon --key Timeout $((IDLE_LOCK_DELAY / 60))"
            run_as_user "qdbus org.kde.screensaver /ScreenSaver Lock"
            ;;
        xfce)
            run_as_user "xfconf-query -c xfce4-screensaver -p /saver/enabled -s true"
            run_as_user "xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -s true"
            run_as_user "xfce4-screensaver-command -l"
            ;;
        hyprland)
            # Lock via loginctl (sends DBus lock signal that hyprlock picks up)
            su "$USERNAME" -c "loginctl lock-session" 2>/dev/null
            # Restart hypridle so idle locking resumes
            run_as_user "hypridle &"
            ;;
    esac
}

do_unlock() {
    log_msg "Device connected - unlocking"
    get_user_env || return 1
    do_screensaver_disable
    send_ha_state "on"
    log_msg "Unlocked"
}

do_lock() {
    log_msg "Device removed - locking"
    get_user_env || return 1
    do_screensaver_enable
    send_ha_state "off"
    log_msg "Locked"
}

case "$ACTION" in
    connect)    do_unlock ;;
    disconnect) do_lock ;;
    *)
        echo "Usage: $0 {connect|disconnect}"
        exit 1
        ;;
esac
