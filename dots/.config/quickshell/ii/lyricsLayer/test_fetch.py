
import sys
import os
import json
# Add the directory to path so we can import
sys.path.append(os.path.expanduser("~/.config/quickshell/ii/lyricsLayer"))

# Mocking some things if needed, but let's try direct import
try:
    from lyrics_backend import fetch_lyrics
except ImportError as e:
    print(f"Import Error: {e}")
    sys.exit(1)

print("Starting fetch test...")
# Clear cache for this test to ensure we hit the network
cache_path = os.path.expanduser("~/.cache/lyrics-layer/James Arthur - Naked.json")
if os.path.exists(cache_path):
    print("Removing cache...")
    os.remove(cache_path)

# Try fetching
print("Fetching 'Naked' by 'James Arthur'...")
res = fetch_lyrics("Naked", "James Arthur")

if res:
    print("SUCCESS: Got lyrics!")
    print(json.dumps(res[:3], indent=2)) # Print first 3 lines
else:
    print("FAILURE: returned None")
    
