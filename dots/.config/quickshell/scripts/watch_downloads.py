import os
import time
import sys

DOWNLOADS_DIR = os.path.expanduser("~/Downloads")
LOG_FILE = "/tmp/qs_popup.log"

def log_popup(type, title, message):
    with open(LOG_FILE, "a") as f:
        f.write(f"{type}|{title}|{message}\n")

def main():
    if not os.path.exists(DOWNLOADS_DIR):
        return

    print(f"Watching {DOWNLOADS_DIR} for new files...")
    
    # Initial snapshot
    before = dict ([(f, None) for f in os.listdir(DOWNLOADS_DIR)])
    
    while True:
        time.sleep(2)
        after = dict ([(f, None) for f in os.listdir(DOWNLOADS_DIR)])
        
        added = [f for f in after if not f in before]
        
        if added:
            for f in added:
                # Ignore partial downloads if possible (crdownload, part)
                if f.endswith(".crdownload") or f.endswith(".part"):
                    continue
                
                print(f"New download: {f}")
                log_popup("good", "Download", f"Completed: {f}|download|complete")
                
        before = after

if __name__ == "__main__":
    main()
