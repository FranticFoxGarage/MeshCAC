#!/bin/bash
# Quick installer for USB Unlock
# Run with: sudo bash install.sh

set -e
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo bash install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL_USER="${SUDO_USER:-$USER}"
if [ "$REAL_USER" = "root" ]; then
    echo "ERROR: Run this with 'sudo', not as root directly."
    exit 1
fi

echo "====================================="
echo "  USB Unlock Installer"
echo "====================================="
echo ""
echo "Installing for user: $REAL_USER"
echo ""

# Patch the username into the script
sed "s/YOUR_USERNAME_HERE/$REAL_USER/" "$SCRIPT_DIR/usb-unlock.sh" > /usr/local/bin/usb-unlock.sh
chmod +x /usr/local/bin/usb-unlock.sh
cp "$SCRIPT_DIR/99-usb-unlock.rules" /etc/udev/rules.d/
udevadm control --reload-rules
udevadm trigger