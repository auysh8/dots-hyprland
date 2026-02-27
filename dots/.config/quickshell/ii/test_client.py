import json, socket, os
s = os.path.join(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"), "quickshell_music.sock")
if os.path.exists(s):
    conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    conn.connect(s)
    conn.sendall(json.dumps({"command": "play", "videoId": "8BiLurrzFRw", "title": "Night Changes", "artist": "One Direction", "artUrl": "https://i.ytimg.com/vi/8BiLurrzFRw/hqdefault.jpg"}).encode() + b'\n')
    print("Sent play command")
    conn.close()
