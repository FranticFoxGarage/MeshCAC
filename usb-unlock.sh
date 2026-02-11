#!/bin/bash

USERNAME="YOUR_USERNAME_HERE" # Leave as placeholder if you use the install script. If installing manually put your username here (use the command whoami and copy paste exact username)
IDLE_LOCK_DELAY=900           # Idle lock delay in seconds (900 = 15 min), used when device is NOT connected otherwise never locks/sleeps

LOG_TAG="usb-unlock"
ACTION="$1"

log_msg() {
    logger -t "$LOG_TAG" "$1"
}

get_user_env() {
    local pid
    pid=$(pgrep -u "$USERNAME" -x cinnamon | head -1)
    if [ -z "$pid" ]; then
        log_msg "ERROR: Could not find cinnamon process for $USERNAME"
        return 1
    fi

    export DBUS_SESSION_BUS_ADDRESS=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$pid/environ 2>/dev/null | cut -d= -f2-)
    export DISPLAY=$(grep -z DISPLAY /proc/$pid/environ 2>/dev/null | cut -d= -f2-)

    if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
        log_msg "ERROR: Could not get DBUS_SESSION_BUS_ADDRESS"
        return 1
    fi
    return 0
}

do_unlock() {
    log_msg "USB key connected - unlocking screen and disabling idle lock"
    get_user_env || return 1
    su - "$USERNAME" -c "DISPLAY=$DISPLAY DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS cinnamon-screensaver-command -d" 2>/dev/null
    su - "$USERNAME" -c "DISPLAY=$DISPLAY DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS dbus-send --session --dest=org.cinnamon.SettingsDaemon.Power --print-reply /org/cinnamon/SettingsDaemon/Power org.freedesktop.DBus.Properties.Set string:'org.cinnamon.SettingsDaemon.Power' string:'IdleActivationEnabled' variant:boolean:false" 2>/dev/null
    su - "$USERNAME" -c "DISPLAY=$DISPLAY DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS gsettings set org.cinnamon.desktop.screensaver lock-enabled false" 2>/dev/null
    su - "$USERNAME" -c "DISPLAY=$DISPLAY DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS gsettings set org.cinnamon.desktop.session idle-delay uint32 0" 2>/dev/null
    log_msg "Screen unlocked, idle lock disabled"
}

do_lock() {
    log_msg "USB key removed - locking screen and re-enabling idle lock"

    get_user_env || return 1
    su - "$USERNAME" -c "DISPLAY=$DISPLAY DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS gsettings set org.cinnamon.desktop.screensaver lock-enabled true" 2>/dev/null
    su - "$USERNAME" -c "DISPLAY=$DISPLAY DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS gsettings set org.cinnamon.desktop.session idle-delay uint32 $IDLE_LOCK_DELAY" 2>/dev/null
    su - "$USERNAME" -c "DISPLAY=$DISPLAY DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS dbus-send --session --dest=org.cinnamon.SettingsDaemon.Power --print-reply /org/cinnamon/SettingsDaemon/Power org.freedesktop.DBus.Properties.Set string:'org.cinnamon.SettingsDaemon.Power' string:'IdleActivationEnabled' variant:boolean:true" 2>/dev/null
    su - "$USERNAME" -c "DISPLAY=$DISPLAY DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS cinnamon-screensaver-command -l" 2>/dev/null
    log_msg "Screen locked, idle lock re-enabled (delay: ${IDLE_LOCK_DELAY}s)"
}

case "$ACTION" in
    connect)
        do_unlock
        ;;
    disconnect)
        do_lock
        ;;
    *)
        echo "Usage: $0 {connect|disconnect}"
        echo ""
        echo "This script is called by udev when the USB key is plugged/unplugged."
        echo "You can test manually by:"
        echo "  sudo $0 connect      # simulate plug in"
        echo "  sudo $0 disconnect   # simulate removal"
        exit 1
        ;;
esac
