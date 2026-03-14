
import sys
import os
import json

# Add the directory to path so we can import dynamically based on script location
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Mocking some things if needed, but let's try direct import
try:
    import lyrics_backend
except ImportError as e:
    print(f"Import Error: {e}")
    sys.exit(1)

print("Starting fetch test...")
# Clear cache for this test to ensure we hit the network
try:
    cache_path = lyrics_backend.get_cache_path("James Arthur", "Naked")
    if cache_path.exists():
        print(f"Removing cache: {cache_path}")
        cache_path.unlink()
except Exception as e:
    print(f"Error clearing cache: {e}")

# Try fetching
print("Fetching 'Naked' by 'James Arthur'...")
lyrics, is_synced, source = lyrics_backend.fetch_lyrics("Naked", "James Arthur")

if lyrics:
    print(f"SUCCESS: Got lyrics from {source} (Synced: {is_synced})")
    print(json.dumps(lyrics[:3], indent=2)) # Print first 3 lines
else:
    print("FAILURE: returned None")
    
