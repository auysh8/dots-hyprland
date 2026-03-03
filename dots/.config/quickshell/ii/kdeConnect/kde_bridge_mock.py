#!/usr/bin/env python3
import json
print(json.dumps({
    "found": True,
    "id": "dev1",
    "name": "My Phone",
    "battery": 85,
    "charging": False,
    "devices": [
        {"id": "dev1", "name": "My Phone", "reachable": True, "battery": 85, "charging": False},
        {"id": "dev2", "name": "Tablet", "reachable": True, "battery": 42, "charging": True},
        {"id": "dev3", "name": "Old Phone", "reachable": False, "battery": -1, "charging": False}
    ]
}))
