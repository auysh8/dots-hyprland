#!/usr/bin/env python3
import os
import sys
import time
import subprocess
import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

# Configuration
LOG_FILE = "/tmp/qs_popup.log"

# Global state tracking to avoid duplicate notifications
state = {
    'ac': 'Unknown',
    'wifi': 'Unknown',
    'bt_count': 0,
    'song': '',
}

def log(category, title, message, cat="generic", act=""):
    """Writes to the log file in the format expected by Quickshell."""
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{category}|{title}|{message}|{cat}|{act}\n")
    except Exception as e:
        print(f"Error writing to log: {e}", file=sys.stderr)

# --- DBus Signal Handlers ---

def bt_handler(interface, changed, invalidated, path):
    """Handles Bluetooth property changes (connection status)."""
    if 'Connected' in changed:
        is_connected = changed['Connected']
        # We need to count total connected devices
        # Since this signal is for a specific device, we should re-scan or just increment/decrement
        # Re-scanning via dbus is safer to get the true count
        bus = dbus.SystemBus()
        manager = dbus.Interface(bus.get_object('org.bluez', '/'), 'org.freedesktop.DBus.ObjectManager')
        objects = manager.GetManagedObjects()
        
        connected_devices = 0
        device_name = "Device"
        
        for path, interfaces in objects.items():
            if 'org.bluez.Device1' in interfaces:
                dev = interfaces['org.bluez.Device1']
                if dev.get('Connected', False):
                    connected_devices += 1
                    if path == path: # This is the device that changed
                        device_name = dev.get('Alias', dev.get('Name', 'Device'))

        if connected_devices > state['bt_count']:
            log("good", "BLUETOOTH", f"Connected: {device_name}", "bluetooth", "connected")
        elif connected_devices < state['bt_count']:
            log("bad", "BLUETOOTH", "Disconnected", "bluetooth", "disconnected")
            
        state['bt_count'] = connected_devices

def mpris_handler(interface, changed, invalidated, path):
    """Handles Media Player property changes."""
    if 'Metadata' in changed:
        metadata = changed['Metadata']
        title = metadata.get('xesam:title', '')
        artist = metadata.get('xesam:artist', [''])[0]
        
        if title:
            song_str = f"{title} - {artist}"
            # Truncate if too long
            if len(song_str) > 40:
                song_str = song_str[:40] + "..."
                
            if song_str != state['song']:
                # Only log if it's a new song and we aren't in initial state
                if state['song'] != "": 
                    log("neutral", "Now Playing", song_str, "media", "playing")
                state['song'] = song_str

# --- UDev Monitoring (Power) ---

def udev_line_handler(source, condition):
    """Reads lines from udevadm monitor."""
    line = source.readline()
    if not line:
        return True # Keep watching
        
    line = line.decode('utf-8').strip()
    
    # We are looking for "change" events on power_supply subsystem
    # Example: KERNEL[1234.56] change   /devices/.../power_supply/AC (power_supply)
    if "change" in line and "power_supply" in line:
        # Check AC status manually when an event occurs
        check_power_status()
        
    return True

def check_power_status():
    """Reads the AC online status from sysfs."""
    try:
        # Find AC adapter
        ac_path = None
        base = "/sys/class/power_supply"
        if os.path.exists(base):
            for dev in os.listdir(base):
                if dev.startswith("AC") or dev.startswith("ADP"):
                    ac_path = os.path.join(base, dev)
                    break
        
        if ac_path and os.path.exists(os.path.join(ac_path, "online")):
            with open(os.path.join(ac_path, "online"), 'r') as f:
                status = f.read().strip()
                
            if status != state['ac']:
                if status == "1":
                    log("good", "POWER", "Plugged In", "battery", "charging")
                else:
                    log("bad", "POWER", "Unplugged", "battery", "unplugged")
                state['ac'] = status
    except Exception as e:
        print(f"Error checking power: {e}", file=sys.stderr)

# --- Disk Space (Polling) ---

def check_disk_space():
    """Checks disk space every minute."""
    try:
        # statvfs would be better but keeping it simple with subprocess for exact matches to `df` output
        result = subprocess.run(['df', '/', '--output=pcent'], capture_output=True, text=True)
        # Output is usually "Use%\n 45%"
        usage_line = result.stdout.strip().split('\n')[-1]
        usage_pct = int(usage_line.replace('%', '').strip())
        
        if usage_pct >= 90:
            log("bad", "SYSTEM", f"Low Disk Space ({usage_pct}%)", "generic", "low")
            
    except Exception as e:
        print(f"Error checking disk: {e}", file=sys.stderr)
        
    return True # Keep running

# --- Main ---

def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    
    # 1. Initial State
    check_power_status()
    # Bluetooth initial count
    try:
        manager = dbus.Interface(bus.get_object('org.bluez', '/'), 'org.freedesktop.DBus.ObjectManager')
        objects = manager.GetManagedObjects()
        count = 0
        for path, interfaces in objects.items():
            if 'org.bluez.Device1' in interfaces and interfaces['org.bluez.Device1'].get('Connected'):
                count += 1
        state['bt_count'] = count
    except:
        pass

    # 2. Setup DBus Signals
    # Bluetooth
    try:
        bus.add_signal_receiver(
            bt_handler,
            dbus_interface='org.freedesktop.DBus.Properties',
            signal_name='PropertiesChanged',
            arg0='org.bluez.Device1',
            path_keyword='path'
        )
    except Exception as e:
        print(f"Failed to set up Bluetooth monitoring: {e}")

    # MPRIS (Music)
    try:
        # Watch for all media players
        bus.add_signal_receiver(
            mpris_handler,
            dbus_interface='org.freedesktop.DBus.Properties',
            signal_name='PropertiesChanged',
            arg0='org.mpris.MediaPlayer2.Player',
            path_keyword='path'
        )
    except Exception as e:
        print(f"Failed to set up MPRIS monitoring: {e}")

    # 3. Setup UDev Monitor
    try:
        # Monitor only power_supply changes
        udev_proc = subprocess.Popen(
            ['udevadm', 'monitor', '--kernel', '--subsystem-match=power_supply'],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL
        )
        GLib.io_add_watch(udev_proc.stdout, GLib.IO_IN, udev_line_handler)
    except Exception as e:
        print(f"Failed to set up UDev monitoring: {e}")
        # Fallback? Timer?
        GLib.timeout_add_seconds(2, lambda: (check_power_status(), True)[1])

    # 4. Setup Disk Timer (every 60s)
    GLib.timeout_add_seconds(60, check_disk_space)
    
    # 5. Network Manager (Simple replacement for polling)
    # Using DBus for NM is verbose, let's stick to polling for WIFI ONLY if user really wants it optimized.
    # But since user asked for specifically DBus for Bluetooth and Udev for Power, let's add a slow poll for Wifi 
    # to avoid complex NM signal handling for now (it's complex to get the SSID efficiently).
    # Reusing the logic from the bash script but cleaner in python?
    # Actually let's just listen to NM state changed signal. It's 'StateChanged' on 'org.freedesktop.NetworkManager'
    
    def nm_handler(state_val):
        # 70 = Connected
        if state_val == 70:
            log("good", "WIFI", "Connected", "wifi", "connected")
        elif state_val == 20 or state_val == 10: # Disconnected
            log("bad", "WIFI", "Disconnected", "wifi", "disconnected")
            
    try:
        bus.add_signal_receiver(
            nm_handler,
            dbus_interface='org.freedesktop.NetworkManager',
            signal_name='StateChanged'
        )
    except:
        pass

    # Run Main Loop
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
