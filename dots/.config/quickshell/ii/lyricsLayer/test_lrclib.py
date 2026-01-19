
import requests
import json

def check_lyrics():
    try:
        # Search for a popular song that might have synced lyrics
        print("Searching...")
        response = requests.get("https://lrclib.net/api/search?q=Bohemian%20Rhapsody%20Queen")
        data = response.json()
        
        if not data:
            print("No results found")
            return

        first_track = data[0]
        print(f"Track: {first_track.get('name')} by {first_track.get('artistName')}")
        print(f"Synced Lyrics Sample:")
        print(first_track.get("syncedLyrics", "")[:500])  # Print first 500 chars

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    check_lyrics()
