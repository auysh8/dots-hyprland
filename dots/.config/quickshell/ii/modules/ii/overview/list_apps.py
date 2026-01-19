#!/usr/bin/env python3
import os
import json
import configparser

def get_apps():
    apps = []
    seen_names = set()
    paths = ["/usr/share/applications", os.path.expanduser("~/.local/share/applications")]
    
    for path in paths:
        if not os.path.exists(path):
            continue
        for root, dirs, files in os.walk(path):
            for file in files:
                if file.endswith(".desktop"):
                    try:
                        full_path = os.path.join(root, file)
                        config = configparser.ConfigParser(interpolation=None)
                        try:
                            config.read(full_path)
                        except:
                            continue
                        if "Desktop Entry" not in config:
                            continue
                        entry = config["Desktop Entry"]
                        if entry.get("NoDisplay", "false").lower() == "true":
                            continue
                        name = entry.get("Name", "")
                        if not name or name in seen_names:
                            continue
                        seen_names.add(name)
                        icon = entry.get("Icon", "application-x-executable")
                        exec_cmd = entry.get("Exec", "")
                        exec_clean = " ".join([part for part in exec_cmd.split() if not part.startswith("%")])
                        if not exec_clean:
                            continue
                        apps.append({"name": name, "icon": icon, "exec": exec_clean, "description": entry.get("Comment", ""), "desktopFile": full_path})
                    except:
                        continue
    apps.sort(key=lambda x: x["name"].lower())
    return apps

if __name__ == "__main__":
    print(json.dumps(get_apps()))
