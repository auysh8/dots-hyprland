from ytmusicapi import YTMusic
import json

yt = YTMusic()
query = "Ed"
print(f"Fetching suggestions for: {query}")

try:
    suggestions = yt.get_search_suggestions(query)
    print(f"Suggestions: {json.dumps(suggestions, indent=2)}")
except Exception as e:
    print(f"Error: {e}")
