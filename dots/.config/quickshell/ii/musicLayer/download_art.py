#!/usr/bin/env python3
import sys
import os
import requests
import hashlib

def main():
    if len(sys.argv) < 2:
        return

    art_url = sys.argv[1]
    if not art_url:
        return

    # Match the logic in MediaPage.qml: Qt.md5(artUrl)
    m = hashlib.md5()
    m.update(art_url.encode('utf-8'))
    file_name = m.hexdigest()
    
    # Path logic from Directories.qml
    # Usually ~/.cache/quickshell/media/coverart/
    cache_dir = os.path.expanduser("~/.cache/quickshell/media/coverart")
    os.makedirs(cache_dir, exist_ok=True)
    
    file_path = os.path.join(cache_dir, file_name)
    
    if os.path.exists(file_path):
        return

    try:
        r = requests.get(art_url, timeout=10)
        if r.status_code == 200:
            with open(file_path, 'wb') as f:
                f.write(r.content)
    except Exception:
        pass

if __name__ == "__main__":
    main()
