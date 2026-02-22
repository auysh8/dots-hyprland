#!/usr/bin/env python3
import subprocess
import json
import shutil
import sys
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "kdeconnect-drawer"
LAST_DEVICE_FILE = CONFIG_DIR / "last_device_id"

def get_dbus_prop(path, interface, prop, user=True):
    """Helper to fetch a property via busctl."""
    if not shutil.which("busctl"):
        return None

    cmd = ["busctl", "--user" if user else "--system", "get-property", 
           "org.kde.kdeconnect", path, interface, prop]
    
    try:
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
        
        if out.startswith('s '): return out[2:].strip('"')
        if out.startswith('i '): return int(out.split()[-1])
        if out.startswith('b '): return "true" in out.lower()
        return out
    except:
        return None

def read_last_device_id():
    try:
        return LAST_DEVICE_FILE.read_text(encoding="utf-8").strip()
    except:
        return ""

def write_last_device_id(device_id):
    if not device_id:
        return
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        LAST_DEVICE_FILE.write_text(device_id, encoding="utf-8")
    except:
        pass

def get_device_ids():
    try:
        raw_ids = subprocess.check_output(
            ["kdeconnect-cli", "-a", "--id-only"],
            text=True,
            stderr=subprocess.DEVNULL
        ).strip()
    except:
        return []
    if not raw_ids:
        return []
    return [line.strip() for line in raw_ids.splitlines() if line.strip()]

def get_device_info(dev_id):
    dev_path = f"/modules/kdeconnect/devices/{dev_id}"
    battery_path = f"{dev_path}/battery"
    info = {
        "id": dev_id,
        "name": get_dbus_prop(dev_path, "org.kde.kdeconnect.device", "name") or dev_id,
        "reachable": bool(get_dbus_prop(dev_path, "org.kde.kdeconnect.device", "isReachable")),
        "battery": -1,
        "charging": False
    }
    charge = get_dbus_prop(battery_path, "org.kde.kdeconnect.device.battery", "charge")
    charging = get_dbus_prop(battery_path, "org.kde.kdeconnect.device.battery", "isCharging")
    if charge is not None:
        info["battery"] = charge
    if charging is not None:
        info["charging"] = charging
    return info

def pick_device(devices, preferred_id):
    if not devices:
        return None
    if preferred_id:
        for dev in devices:
            if dev["id"] == preferred_id and dev["reachable"]:
                return dev
    for dev in devices:
        if dev["reachable"]:
            return dev
    if preferred_id:
        for dev in devices:
            if dev["id"] == preferred_id:
                return dev
    return devices[0]

def main():
    data = {
        "found": False,
        "id": "",
        "name": "No Device",
        "battery": -1,
        "charging": False,
        "devices": []
    }

    preferred_arg = sys.argv[1].strip() if len(sys.argv) > 1 else ""
    preferred_id = preferred_arg or read_last_device_id()
    device_ids = get_device_ids()
    devices = [get_device_info(dev_id) for dev_id in device_ids]
    selected = pick_device(devices, preferred_id)

    data["devices"] = devices
    if selected:
        data["id"] = selected["id"]
        data["name"] = selected["name"]
        data["battery"] = selected["battery"]
        data["charging"] = selected["charging"]
        data["found"] = selected["reachable"]
        write_last_device_id(selected["id"])

    print(json.dumps(data))

if __name__ == "__main__":
    main()
