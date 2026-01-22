#!/usr/bin/env python3
import subprocess
import json
import shutil
import sys

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

def main():
    data = {
        "found": False,
        "id": "",
        "name": "No Device",
        "battery": -1,
        "charging": False
    }

    try:
        raw_ids = subprocess.check_output(
            ["kdeconnect-cli", "-a", "--id-only"], 
            text=True, 
            stderr=subprocess.DEVNULL
        ).strip()
    except:
        print(json.dumps(data))
        return

    if not raw_ids:
        print(json.dumps(data))
        return

    dev_id = raw_ids.split('\n')[0].strip()
    
    if dev_id:
        data["found"] = True
        data["id"] = dev_id

        name = get_dbus_prop(
            f"/modules/kdeconnect/devices/{dev_id}", 
            "org.kde.kdeconnect.device", 
            "name"
        )
        if name: data["name"] = name

        bat_path = f"/modules/kdeconnect/devices/{dev_id}/battery"
        bat_iface = "org.kde.kdeconnect.device.battery"
        
        charge = get_dbus_prop(bat_path, bat_iface, "charge")
        is_charging = get_dbus_prop(bat_path, bat_iface, "isCharging")

        if charge is not None: data["battery"] = charge
        if is_charging is not None: data["charging"] = is_charging

    print(json.dumps(data))

if __name__ == "__main__":
    main()