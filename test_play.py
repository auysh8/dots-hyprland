import json
import subprocess
import time

msg = {
    "command": "play",
    "videoId": "dQw4w9WgXcQ",
    "title": "Never Gonna Give You Up",
    "artist": "Rick Astley",
    "artUrl": ""
}

proc = subprocess.Popen(["dots/.config/quickshell/ii/musicLayer/venv/bin/python", "dots/.config/quickshell/ii/musicLayer/music_backend.py"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
proc.stdin.write(json.dumps(msg) + "\n")
proc.stdin.flush()

for i in range(10):
    line = proc.stdout.readline()
    if line:
        print("Backend said:", line.strip())
    time.sleep(0.5)

proc.terminate()
