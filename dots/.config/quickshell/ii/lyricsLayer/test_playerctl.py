import subprocess
import sys

print("Testing playerctl...", file=sys.stderr)
try:
    s = subprocess.run(["playerctl", "-l"], capture_output=True, text=True)
    print(f"Players: {s.stdout.strip()}", file=sys.stderr)
    
    players = s.stdout.strip().splitlines()
    for p in players:
        print(f"Checking {p}...", file=sys.stderr)
        m = subprocess.run(["playerctl", "-p", p, "metadata", "--format", "{{title}} - {{artist}}"], capture_output=True, text=True)
        print(f"Info: {m.stdout.strip()}", file=sys.stderr)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
