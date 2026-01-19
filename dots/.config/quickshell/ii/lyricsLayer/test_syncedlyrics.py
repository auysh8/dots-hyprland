
import syncedlyrics
import sys

# Test searching for enhanced lyrics
term = "Beggin Maneskin"
print(f"Searching for enhanced lyrics for: {term}...")

try:
    # enhanced=True tells it to look for word-by-word if possible
    lrc = syncedlyrics.search(term, enhanced=True)
    if lrc:
        print("FOUND LYRICS (First 500 chars):")
        print(lrc[:500])
        if "<" in lrc and ">" in lrc:
             print("\n VERDICT: Enhanced Lyrics FOUND! ✅")
        else:
             print("\n VERDICT: Standard Lyrics Only. ❌")
    else:
        print("No lyrics found.")
except Exception as e:
    print(f"Error: {e}")
