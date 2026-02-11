# MeshCAC
I saw an air force recuriter use what looked like a debit card to log into his computer once. I now carry a T1000e with me so why not use it as a way to unlock my PC? I use Linux Mint (Cinnamon) desktop - this will work in Linux Mint 22.1 but might not for other versions or distros so no promises. Your password continues to work normally at all times, this just adds another way to unlock/lock.

## Configuration
Edit `usb-unlock.sh` to change `IDLE_LOCK_DELAY` to whatever you want. Seconds before idle lock kicks in when device is NOT connected (default: 900 = 15 minutes)

Edit `99-usb-unlock.rules` to change the device. Plug in "whatever" you are wanting and run ```lsusb``` look for your device, in my case its `Bus 001 Device 023: ID 239a:8029 Adafruit T1000-E-BOOT`
Update ```ATTR{idVendor}=="239a", ATTR{idProduct}=="8029"``` both plugged in and removed lines with your devices ID xxxx:xxxx

## Install
```sudo bash install.sh``` Do this after you make the above changes. If I cared id have this script promt you for the above... maybe one day

## Debugging / Logs
All actions are logged to syslog with the tag `usb-unlock`.
```bash
# View all usb-unlock logs
journalctl -t usb-unlock

# Test manually without plugging/unplugging
sudo /usr/local/bin/usb-unlock.sh connect
sudo /usr/local/bin/usb-unlock.sh disconnect

# Watch raw udev events (useful if the rule isn't firing)
sudo udevadm monitor --environment --udev

# Reload rules after editing the udev rule file
sudo udevadm control --reload-rules
```

## Uninstall
```bash
sudo rm /usr/local/bin/usb-unlock.sh
sudo rm /etc/udev/rules.d/99-usb-unlock.rules
sudo udevadm control --reload-rules
```
Your screensaver and idle lock settings will stay at whatever they were in when you uninstall. IE; If the device was connected you may want to manually re-enable idle lock in your system settings
