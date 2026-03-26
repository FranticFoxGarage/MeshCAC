# MeshCAC

I saw an air force recuriter use what looked like a debit card to log into his computer once. I now carry a T1000e with me so why not use it as a way to unlock my PC? I use Linux Mint (Cinnamon) desktop - this will work in Linux Mint 22.1 but might not for other versions or distros so no promises. Your password continues to work normally at all times, this just adds another way to unlock/lock. 
I also added a HomeAssistant option you just need to provide a long access token
Profile (bottom left, user icon)> Security> Long-Lived Access Tokens> Create Token (bottom of the page).

## Install

`sudo bash install.sh`

The install script will walk you through everything - device selection (plug in / unplug to auto-detect), Home Assistant setup if you want it, idle delay, etc. If you have an existing install it'll use your current settings as defaults.

## Debugging / Logs

All actions are logged to syslog with the tag `meshcac`.

```
# View all meshcac logs
journalctl -t meshcac

# Test manually without plugging/unplugging
sudo /usr/local/bin/usb-unlock.sh connect
sudo /usr/local/bin/usb-unlock.sh disconnect

# Watch raw udev events (useful if the rule isn't firing)
sudo udevadm monitor --environment --udev

# Reload rules after editing the udev rule file
sudo udevadm control --reload-rules
```

## Uninstall

```
sudo rm /usr/local/bin/usb-unlock.sh
sudo rm /usr/local/bin/meshcac-ha-monitor.sh
sudo rm /etc/udev/rules.d/99-meshcac.rules
sudo rm -rf /etc/meshcac
sudo udevadm control --reload-rules
systemctl --user disable --now meshcac-ha-monitor.service
rm ~/.config/systemd/user/meshcac-ha-monitor.service
```
Or just use the uninstall option in installer

Your screensaver and idle lock settings will stay at whatever they were in when you uninstall. IE; If the device was connected you may want to manually re-enable idle lock in your system settings

## Known Issues

Updating the T1000e puts it in DFU mode making it visable as a mass storage device. This makes it show up as a diffrent device thus locking your computer.
