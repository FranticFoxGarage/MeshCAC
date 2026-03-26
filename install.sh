#!/bin/bash
# MeshCAC Installer
# https://github.com/FranticFoxGarage/MeshCAC

set -e

REPO_RAW="https://raw.githubusercontent.com/FranticFoxGarage/MeshCAC/main"
INSTALL_BIN="/usr/local/bin"
INSTALL_CONF="/etc/meshcac"
UDEV_RULES="/etc/udev/rules.d/99-meshcac.rules"
OLD_UDEV_RULES="/etc/udev/rules.d/99-usb-unlock.rules"

# ---- Colours ----
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[*]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
prompt()  { echo -e "${BOLD}[?]${NC} $1"; }

# ---- Root check ----
[ "$(id -u)" -ne 0 ] && error "Run with sudo: sudo bash install.sh"

REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_UID=$(id -u "$REAL_USER")
REAL_HOME=$(eval echo ~"$REAL_USER")

echo ""
echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}║          MeshCAC Installer           ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""

# ---- Existing install detection ----
EXISTING_INSTALL=false
EXISTING_CONF=""
if [ -f "$INSTALL_CONF/meshcac.conf" ] || [ -f "/usr/local/bin/usb-unlock.sh" ]; then
    EXISTING_INSTALL=true
    [ -f "$INSTALL_CONF/meshcac.conf" ] && EXISTING_CONF="$INSTALL_CONF/meshcac.conf"
    [ -z "$EXISTING_CONF" ] && [ -f "/usr/local/bin/usb-unlock.sh" ] && EXISTING_CONF=""
fi

if [ -f "$OLD_UDEV_RULES" ] && [ ! -f "$UDEV_RULES" ]; then
    warn "Found old rules file (99-usb-unlock.rules) - will replace with 99-meshcac.rules"
fi

if $EXISTING_INSTALL; then
    warn "Existing MeshCAC install detected."
    echo ""
    echo "  1) Update / reinstall (keep existing config as defaults)"
    echo "  2) Fresh install (overwrite everything)"
    echo "  3) Uninstall"
    echo "  4) Abort"
    echo ""
    prompt "Choice [1-4]:"
    read -r INSTALL_MODE
    case "$INSTALL_MODE" in
        1) info "Updating - existing config values will be used as defaults" ;;
        2) info "Fresh install" ; EXISTING_CONF="" ;;
        3)
            echo ""
            warn "This will remove all MeshCAC files and restore idle lock settings."
            prompt "Are you sure? [y/N]:"
            read -r CONFIRM_UNINSTALL
            [[ ! "$CONFIRM_UNINSTALL" =~ ^[Yy] ]] && echo "Aborted." && exit 0

            UNINSTALL_USER="${SUDO_USER:-$(whoami)}"
            UNINSTALL_UID=$(id -u "$UNINSTALL_USER")
            UNINSTALL_HOME=$(eval echo ~"$UNINSTALL_USER")

            # Load config before removing it so we can restore screensaver settings
            UNINSTALL_CONF="$INSTALL_CONF/meshcac.conf"
            if [ -f "$UNINSTALL_CONF" ]; then
                source "$UNINSTALL_CONF"
                UNINSTALL_DE="${DESKTOP_ENV:-cinnamon}"
            else
                UNINSTALL_DE="cinnamon"
            fi

            info "Stopping HA monitor service..."
            su - "$UNINSTALL_USER" -c "XDG_RUNTIME_DIR=/run/user/$UNINSTALL_UID systemctl --user disable --now meshcac-ha-monitor.service" 2>/dev/null || true

            info "Removing files..."
            rm -f "$INSTALL_BIN/usb-unlock.sh"
            rm -f "$INSTALL_BIN/meshcac-ha-monitor.sh"
            rm -f "$UDEV_RULES"
            rm -f "$OLD_UDEV_RULES"
            rm -rf "$INSTALL_CONF"
            rm -f "$UNINSTALL_HOME/.config/systemd/user/meshcac-ha-monitor.service"

            info "Reloading udev rules..."
            udevadm control --reload-rules

            info "Restoring screensaver settings..."
            case "$UNINSTALL_DE" in
                cinnamon)
                    su - "$UNINSTALL_USER" -c "gsettings set org.cinnamon.desktop.screensaver lock-enabled true" 2>/dev/null || true
                    su - "$UNINSTALL_USER" -c "gsettings set org.cinnamon.desktop.session idle-delay uint32 900" 2>/dev/null || true
                    ;;
                gnome)
                    su - "$UNINSTALL_USER" -c "gsettings set org.gnome.desktop.screensaver lock-enabled true" 2>/dev/null || true
                    su - "$UNINSTALL_USER" -c "gsettings set org.gnome.desktop.session idle-delay uint32 900" 2>/dev/null || true
                    ;;
            esac

            echo ""
            success "MeshCAC uninstalled"
            echo ""
            exit 0
            ;;
        4) echo "Aborted." ; exit 0 ;;
        *) error "Invalid choice" ;;
    esac
else
    INSTALL_MODE="2"
fi

# Load existing config as defaults if updating
load_existing_value() {
    local key="$1"
    if [ -n "$EXISTING_CONF" ]; then
        grep "^${key}=" "$EXISTING_CONF" 2>/dev/null | cut -d= -f2- | tr -d '"'
    fi
}

if $EXISTING_INSTALL && [ "$INSTALL_MODE" = "1" ] && [ -n "$EXISTING_CONF" ]; then
    echo ""
    echo -e "${BOLD}── Current config ───────────────────────${NC}"
    echo -e "  User:          $(load_existing_value USERNAME)"
    echo -e "  Desktop:       $(load_existing_value DESKTOP_ENV)"
    echo -e "  Device:        $(load_existing_value USB_VENDOR):$(load_existing_value USB_PRODUCT)  serial=$(load_existing_value USB_SERIAL)"
    echo -e "  Idle delay:    $(load_existing_value IDLE_LOCK_DELAY)s"
    HA_HOST_EXISTING=$(load_existing_value HA_HOST)
    HA_ENTITY_EXISTING=$(load_existing_value HA_ENTITY)
    [ -n "$HA_HOST_EXISTING" ] && echo -e "  HA:            $HA_HOST_EXISTING → $HA_ENTITY_EXISTING"
    echo ""
fi

echo ""
echo -e "${BOLD}── Step 1: Username ─────────────────────${NC}"
DEFAULT_USER=$(load_existing_value "USERNAME")
[ -z "$DEFAULT_USER" ] && DEFAULT_USER="$REAL_USER"
prompt "Username to unlock for [${DEFAULT_USER}]:"
read -r INPUT_USER
[ -z "$INPUT_USER" ] && INPUT_USER="$DEFAULT_USER"
id "$INPUT_USER" &>/dev/null || error "User '$INPUT_USER' not found"
success "User: $INPUT_USER"

echo ""
echo -e "${BOLD}── Step 2: Desktop Environment ──────────${NC}"
DEFAULT_DE=$(load_existing_value "DESKTOP_ENV")
[ -z "$DEFAULT_DE" ] && DEFAULT_DE="cinnamon"

# Try to auto-detect
if pgrep -u "$INPUT_USER" -x cinnamon &>/dev/null; then
    DETECTED_DE="cinnamon"
elif pgrep -u "$INPUT_USER" -x gnome-shell &>/dev/null; then
    DETECTED_DE="gnome"
elif pgrep -u "$INPUT_USER" -x plasmashell &>/dev/null; then
    DETECTED_DE="kde"
elif pgrep -u "$INPUT_USER" -x xfce4-session &>/dev/null; then
    DETECTED_DE="xfce"
else
    DETECTED_DE=""
fi

if [ -n "$DETECTED_DE" ]; then
    success "Detected: $DETECTED_DE"
    prompt "Use $DETECTED_DE? [Y/n]:"
    read -r CONFIRM_DE
    if [[ "$CONFIRM_DE" =~ ^[Nn] ]]; then
        DETECTED_DE=""
    fi
fi

if [ -z "$DETECTED_DE" ]; then
    echo "  1) cinnamon"
    echo "  2) gnome"
    echo "  3) kde"
    echo "  4) xfce"
    prompt "Desktop environment [default: $DEFAULT_DE]:"
    read -r DE_CHOICE
    case "$DE_CHOICE" in
        1|cinnamon) DETECTED_DE="cinnamon" ;;
        2|gnome)    DETECTED_DE="gnome" ;;
        3|kde)      DETECTED_DE="kde" ;;
        4|xfce)     DETECTED_DE="xfce" ;;
        "")         DETECTED_DE="$DEFAULT_DE" ;;
        *)          error "Invalid choice" ;;
    esac
fi
INPUT_DE="$DETECTED_DE"
success "Desktop environment: $INPUT_DE"

echo ""
echo -e "${BOLD}── Step 3: USB Device ───────────────────${NC}"

DEFAULT_VENDOR=$(load_existing_value "USB_VENDOR")
DEFAULT_PRODUCT=$(load_existing_value "USB_PRODUCT")
DEFAULT_SERIAL=$(load_existing_value "USB_SERIAL")

echo "  1) Auto-detect (plug in / unplug device)"
echo "  2) Manual entry"
[ -n "$DEFAULT_VENDOR" ] && echo "  3) Keep existing ($DEFAULT_VENDOR:$DEFAULT_PRODUCT serial=$DEFAULT_SERIAL)"
echo ""
prompt "Choice:"
read -r DEVICE_MODE

case "$DEVICE_MODE" in
    1)
        info "Taking snapshot of current USB devices..."
        BEFORE=$(lsusb)

        echo ""
        prompt "Plug in your device now, then wait..."
        echo ""

        TIMEOUT=30
        ELAPSED=0
        NEW_LINE=""
        while [ $ELAPSED -lt $TIMEOUT ]; do
            AFTER=$(lsusb)
            NEW_LINE=$(diff <(echo "$BEFORE") <(echo "$AFTER") | grep '^>' | sed 's/^> //' | head -1)
            if [ -n "$NEW_LINE" ]; then
                break
            fi
            sleep 0.5
            ELAPSED=$((ELAPSED + 1))
        done

        [ -z "$NEW_LINE" ] && error "No new USB device detected within ${TIMEOUT}s"

        success "Detected: $NEW_LINE"

        # Parse vendor:product and bus/device from lsusb line
        # Format: "Bus 001 Device 023: ID 239a:8029 ..."
        ID_PART=$(echo "$NEW_LINE" | grep -oP 'ID \K[0-9a-fA-F]{4}:[0-9a-fA-F]{4}')
        INPUT_VENDOR=$(echo "$ID_PART" | cut -d: -f1)
        INPUT_PRODUCT=$(echo "$ID_PART" | cut -d: -f2)
        BUS=$(echo "$NEW_LINE" | grep -oP 'Bus \K[0-9]+')
        DEV=$(echo "$NEW_LINE" | grep -oP 'Device \K[0-9]+')

        # Get serial via udevadm using the exact bus/device path
        INPUT_SERIAL=""
        if [ -n "$BUS" ] && [ -n "$DEV" ]; then
            DEVPATH=$(printf "/dev/bus/usb/%03d/%03d" "$((10#$BUS))" "$((10#$DEV))")
            INPUT_SERIAL=$(udevadm info "$DEVPATH" 2>/dev/null | grep 'ID_SERIAL_SHORT=' | cut -d= -f2)
        fi

        if [ -n "$INPUT_SERIAL" ]; then
            success "Serial: $INPUT_SERIAL"
            echo ""
            prompt "Unplug the device to confirm this is the correct one, then press Enter..."
            BEFORE_UNPLUG=$(lsusb)
            read -r _
            ELAPSED=0
            while [ $ELAPSED -lt $TIMEOUT ]; do
                AFTER_UNPLUG=$(lsusb)
                REMOVED=$(diff <(echo "$BEFORE_UNPLUG") <(echo "$AFTER_UNPLUG") | grep '^<' | sed 's/^< //' | head -1)
                if [ -n "$REMOVED" ]; then
                    break
                fi
                sleep 0.5
                ELAPSED=$((ELAPSED + 1))
            done
            if echo "$REMOVED" | grep -q "$INPUT_VENDOR:$INPUT_PRODUCT"; then
                success "Device confirmed"
            else
                warn "Removed device didn't match - proceeding anyway"
            fi
        else
            warn "Could not read serial number from device"
            echo ""
            prompt "Enter serial manually (or leave blank to match any device with this vendor:product):"
            read -r INPUT_SERIAL
        fi
        ;;

    2)
        echo ""
        info "Run 'lsusb' in another terminal to find your device ID (format: xxxx:xxxx)"
        prompt "Vendor ID (e.g. 239a):"
        read -r INPUT_VENDOR
        prompt "Product ID (e.g. 8029):"
        read -r INPUT_PRODUCT
        info "Plug in your device and run: udevadm info -a -n /dev/ttyUSB0 | grep serial"
        prompt "Serial number (leave blank to skip):"
        read -r INPUT_SERIAL
        ;;

    3)
        [ -z "$DEFAULT_VENDOR" ] && error "No existing device config found"
        INPUT_VENDOR="$DEFAULT_VENDOR"
        INPUT_PRODUCT="$DEFAULT_PRODUCT"
        INPUT_SERIAL="$DEFAULT_SERIAL"
        success "Keeping existing: $INPUT_VENDOR:$INPUT_PRODUCT serial=$INPUT_SERIAL"
        ;;

    *) error "Invalid choice" ;;
esac

[ -z "$INPUT_VENDOR" ] && error "Vendor ID required"
[ -z "$INPUT_PRODUCT" ] && error "Product ID required"
[ -z "$INPUT_SERIAL" ] && warn "No serial set - ANY device with $INPUT_VENDOR:$INPUT_PRODUCT will act as the key"
success "Device: $INPUT_VENDOR:$INPUT_PRODUCT  serial=${INPUT_SERIAL:-<any>}"

echo ""
echo -e "${BOLD}── Step 4: Home Assistant (optional) ────${NC}"
echo ""

DEFAULT_HA_HOST=$(load_existing_value "HA_HOST")
DEFAULT_HA_TOKEN=$(load_existing_value "HA_TOKEN")
DEFAULT_HA_IP=$(load_existing_value "HA_IP")
DEFAULT_HA_ENTITY=$(load_existing_value "HA_ENTITY")
DEFAULT_HA_FRIENDLY=$(load_existing_value "HA_FRIENDLY")

[ -n "$DEFAULT_HA_HOST" ] && info "Current: $DEFAULT_HA_HOST"
info "Paste your HA URL, press Enter to keep existing, or type 'none' to disable"
prompt "HA URL [${DEFAULT_HA_HOST:-not set}]:"
read -r HA_RAW

INPUT_HA_TOKEN=""
INPUT_HA_HOST=""
INPUT_HA_IP=""
INPUT_HA_ENTITY=""
INPUT_HA_FRIENDLY=""

# Keep existing if Enter pressed and existing config present
if [ -z "$HA_RAW" ] && [ -n "$DEFAULT_HA_HOST" ]; then
    HA_RAW="https://$DEFAULT_HA_HOST"
fi

if [ "$HA_RAW" = "none" ]; then
    info "Disabling Home Assistant"
elif [ -n "$HA_RAW" ]; then
    # Strip trailing slashes and paths - just need protocol + host
    HA_PROTO=$(echo "$HA_RAW" | grep -oP '^https?')
    HA_HOST_EXTRACTED=$(echo "$HA_RAW" | sed -E 's|^https?://||' | cut -d'/' -f1)

    if [ -z "$HA_HOST_EXTRACTED" ]; then
        warn "Could not parse host from URL - enter manually"
        prompt "HA hostname or IP:"
        read -r HA_HOST_EXTRACTED
        HA_PROTO="https"
    fi

    success "Host: $HA_HOST_EXTRACTED  (${HA_PROTO:-https})"
    INPUT_HA_HOST="$HA_HOST_EXTRACTED"

    # DNS lookup
    info "Looking up IP for $HA_HOST_EXTRACTED..."
    LOOKED_UP_IP=""

    if command -v dig &>/dev/null; then
        LOOKED_UP_IP=$(dig +short "$HA_HOST_EXTRACTED" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    fi
    if [ -z "$LOOKED_UP_IP" ] && command -v getent &>/dev/null; then
        LOOKED_UP_IP=$(getent hosts "$HA_HOST_EXTRACTED" 2>/dev/null | awk '{print $1}' | head -1)
    fi
    if [ -z "$LOOKED_UP_IP" ] && command -v host &>/dev/null; then
        LOOKED_UP_IP=$(host "$HA_HOST_EXTRACTED" 2>/dev/null | grep 'has address' | awk '{print $NF}' | head -1)
    fi

    if [ -n "$LOOKED_UP_IP" ]; then
        success "Resolved IP: $LOOKED_UP_IP"
        prompt "Use this IP? [Y/n]:"
        read -r CONFIRM_IP
        if [[ "$CONFIRM_IP" =~ ^[Nn] ]]; then
            LOOKED_UP_IP=""
        fi
    fi

    if [ -z "$LOOKED_UP_IP" ]; then
        prompt "Enter IP manually (or leave blank to skip --resolve):"
        read -r LOOKED_UP_IP
    fi
    INPUT_HA_IP="$LOOKED_UP_IP"

    DEFAULT_HA_TOKEN=$(load_existing_value "HA_TOKEN")
    prompt "HA long-lived access token [${DEFAULT_HA_TOKEN:+existing}]:"
    read -r INPUT_HA_TOKEN
    [ -z "$INPUT_HA_TOKEN" ] && INPUT_HA_TOKEN="$DEFAULT_HA_TOKEN"
    [ -z "$INPUT_HA_TOKEN" ] && error "HA token required when HA URL is set"

    DEFAULT_ENTITY=$(load_existing_value "HA_ENTITY")
    [ -z "$DEFAULT_ENTITY" ] && DEFAULT_ENTITY="binary_sensor.office_pc_lock"
    prompt "HA entity ID [${DEFAULT_ENTITY}]:"
    read -r INPUT_HA_ENTITY
    [ -z "$INPUT_HA_ENTITY" ] && INPUT_HA_ENTITY="$DEFAULT_ENTITY"

    DEFAULT_FRIENDLY=$(load_existing_value "HA_FRIENDLY")
    [ -z "$DEFAULT_FRIENDLY" ] && DEFAULT_FRIENDLY="PC Lock"
    prompt "HA friendly name [${DEFAULT_FRIENDLY}]:"
    read -r INPUT_HA_FRIENDLY
    [ -z "$INPUT_HA_FRIENDLY" ] && INPUT_HA_FRIENDLY="$DEFAULT_FRIENDLY"
else
    info "Skipping Home Assistant"
fi

echo ""
echo -e "${BOLD}── Step 5: Idle lock delay ───────────────${NC}"
DEFAULT_DELAY=$(load_existing_value "IDLE_LOCK_DELAY")
[ -z "$DEFAULT_DELAY" ] && DEFAULT_DELAY="900"
prompt "Idle lock delay in seconds when device is removed [${DEFAULT_DELAY}]:"
read -r INPUT_DELAY
[ -z "$INPUT_DELAY" ] && INPUT_DELAY="$DEFAULT_DELAY"
success "Idle delay: ${INPUT_DELAY}s ($(( INPUT_DELAY / 60 )) min)"

# ---- Download files ----
echo ""
echo -e "${BOLD}── Step 6: Downloading files ────────────${NC}"

download_file() {
    local filename="$1"
    local dest="$2"
    info "Downloading $filename..."
    if ! curl -fsSL "$REPO_RAW/$filename" -o "$dest"; then
        error "Failed to download $filename from $REPO_RAW/$filename"
    fi
    success "Downloaded $filename"
}

TMP_DIR=$(mktemp -d)
download_file "usb-unlock.sh" "$TMP_DIR/usb-unlock.sh"
download_file "meshcac-ha-monitor.sh" "$TMP_DIR/meshcac-ha-monitor.sh"

# ---- Write config ----
echo ""
echo -e "${BOLD}── Step 7: Writing config ───────────────${NC}"

mkdir -p "$INSTALL_CONF"
cat > "$INSTALL_CONF/meshcac.conf" <<EOF
# MeshCAC Configuration
# Generated by install.sh on $(date)

USERNAME="$INPUT_USER"
IDLE_LOCK_DELAY=$INPUT_DELAY
DESKTOP_ENV="$INPUT_DE"

USB_VENDOR="$INPUT_VENDOR"
USB_PRODUCT="$INPUT_PRODUCT"
USB_SERIAL="$INPUT_SERIAL"

HA_TOKEN="$INPUT_HA_TOKEN"
HA_HOST="$INPUT_HA_HOST"
HA_IP="$INPUT_HA_IP"
HA_ENTITY="$INPUT_HA_ENTITY"
HA_FRIENDLY="$INPUT_HA_FRIENDLY"
EOF
chmod 640 "$INSTALL_CONF/meshcac.conf"
chown root:"$INPUT_USER" "$INSTALL_CONF/meshcac.conf"
success "Config written to $INSTALL_CONF/meshcac.conf"

# ---- Write udev rules ----
SERIAL_ADD_ATTR=""
SERIAL_REMOVE_ENV=""
if [ -n "$INPUT_SERIAL" ]; then
    SERIAL_ADD_ATTR=", ATTRS{serial}==\"$INPUT_SERIAL\""
    SERIAL_REMOVE_ENV=", ENV{ID_SERIAL_SHORT}==\"$INPUT_SERIAL\""
fi

cat > "$UDEV_RULES" <<EOF
# MeshCAC - USB unlock udev rules
# Generated by install.sh on $(date)

ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="$INPUT_VENDOR", ATTR{idProduct}=="$INPUT_PRODUCT"${SERIAL_ADD_ATTR}, RUN+="/usr/local/bin/usb-unlock.sh connect"

ACTION=="remove", SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="$INPUT_VENDOR", ENV{ID_MODEL_ID}=="$INPUT_PRODUCT"${SERIAL_REMOVE_ENV}, RUN+="/usr/local/bin/usb-unlock.sh disconnect"
EOF
success "Udev rules written to $UDEV_RULES"

# Remove old rules file if present
if [ -f "$OLD_UDEV_RULES" ]; then
    rm -f "$OLD_UDEV_RULES"
    success "Removed old rules file (99-usb-unlock.rules)"
fi

# ---- Install scripts ----
install -m 755 "$TMP_DIR/usb-unlock.sh" "$INSTALL_BIN/usb-unlock.sh"
install -m 755 "$TMP_DIR/meshcac-ha-monitor.sh" "$INSTALL_BIN/meshcac-ha-monitor.sh"

# Remove old script if present
[ -f "/usr/local/bin/usb-unlock.sh.old" ] && rm -f "/usr/local/bin/usb-unlock.sh.old"
success "Scripts installed to $INSTALL_BIN"

# ---- Systemd user service (HA monitor) ----
if [ -n "$INPUT_HA_TOKEN" ]; then
    echo ""
    echo -e "${BOLD}── Step 8: HA monitor service ───────────${NC}"

    SERVICE_DIR="$REAL_HOME/.config/systemd/user"
    mkdir -p "$SERVICE_DIR"
    chown "$INPUT_USER:$INPUT_USER" "$REAL_HOME/.config" "$REAL_HOME/.config/systemd" "$SERVICE_DIR" 2>/dev/null || true

    cat > "$SERVICE_DIR/meshcac-ha-monitor.service" <<EOF
[Unit]
Description=MeshCAC Home Assistant State Monitor
After=graphical-session.target

[Service]
ExecStart=$INSTALL_BIN/meshcac-ha-monitor.sh
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
    chown "$INPUT_USER:$INPUT_USER" "$SERVICE_DIR/meshcac-ha-monitor.service"
    success "Service file written"

    # Enable linger so user services start on boot without login
    loginctl enable-linger "$INPUT_USER"

    # Enable and start the service
    if su - "$INPUT_USER" -c "XDG_RUNTIME_DIR=/run/user/$REAL_UID systemctl --user daemon-reload"; then
        if su - "$INPUT_USER" -c "XDG_RUNTIME_DIR=/run/user/$REAL_UID systemctl --user enable --now meshcac-ha-monitor.service"; then
            success "HA monitor service enabled and started"
        else
            warn "Service enable failed - check: journalctl --user -u meshcac-ha-monitor.service"
        fi
    else
        warn "Could not reload systemd user daemon"
    fi
fi

# ---- Reload udev ----
echo ""
info "Reloading udev rules..."
udevadm control --reload-rules
success "Udev rules reloaded"

# ---- Cleanup ----
rm -rf "$TMP_DIR"

# ---- Summary ----
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║        Installation Complete!        ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "  User:          $INPUT_USER"
echo -e "  Desktop:       $INPUT_DE"
echo -e "  Device:        $INPUT_VENDOR:$INPUT_PRODUCT  serial=${INPUT_SERIAL:-<any>}"
echo -e "  Idle delay:    ${INPUT_DELAY}s"
[ -n "$INPUT_HA_HOST" ] && echo -e "  HA:            $INPUT_HA_HOST → $INPUT_HA_ENTITY"
echo ""
echo -e "  Test with:"
echo -e "    sudo /usr/local/bin/usb-unlock.sh connect"
echo -e "    sudo /usr/local/bin/usb-unlock.sh disconnect"
echo ""
echo -e "  Logs: journalctl -t meshcac -f"
echo ""
