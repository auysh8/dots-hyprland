#!/bin/bash
# Test canvas fetcher with multiple sources

# Support --album-id flag
if [ "$1" = "--album-id" ]; then
    ALBUM_ID="$2"
    if [ -z "$ALBUM_ID" ]; then
        echo "Usage: $0 --album-id <album_id>"
        echo "Example: $0 --album-id 1440935467"
        exit 1
    fi
    echo "=========================================="
    echo "Testing Canvas for Album ID: '$ALBUM_ID'"
    echo "=========================================="
    echo ""
    echo "--- ArchiveTune API (Album ID) ---"
    curl -s "https://artwork-archivetune.koiiverse.cloud/?id=$ALBUM_ID" | python3 -m json.tool 2>/dev/null || echo "Failed to fetch from ArchiveTune"
    echo ""
    echo "--- canvas_fetcher.py --album-id ---"
    python3 canvas_fetcher.py --album-id "$ALBUM_ID" | python3 -m json.tool
    echo ""
    echo "=========================================="
    exit 0
fi

# Song/artist mode
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <song_title> <artist_name> [album]"
    echo "       $0 --album-id <album_id>"
    echo "Example: $0 \"Perfect\" \"Ed Sheeran\" \"÷ (Divide)\""
    exit 1
fi

SONG="$1"
ARTIST="$2"
ALBUM="${3:-}"

echo "=========================================="
echo "Testing Canvas for: '$SONG' by '$ARTIST'"
[ -n "$ALBUM" ] && echo "Album: '$ALBUM'"
echo "=========================================="

# Test 1: ArchiveTune API directly
echo ""
echo "--- 1. ArchiveTune API ---"
ARCHIVE_URL="https://artwork-archivetune.koiiverse.cloud/?s=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$SONG'))")&a=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$ARTIST'))")"
[ -n "$ALBUM" ] && ARCHIVE_URL="$ARCHIVE_URL&al=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$ALBUM'))")"
curl -s "$ARCHIVE_URL" | python3 -m json.tool 2>/dev/null || echo "Failed to fetch from ArchiveTune"

# Test 2: Monochrome APIs (Tidal)
echo ""
echo "--- 2. Monochrome Instances (Tidal) ---"
QUERY="$ARTIST - $SONG"
for BASE in "https://eu-central.monochrome.tf/" "https://us-west.monochrome.tf/" "https://arran.monochrome.tf/" "https://api.monochrome.tf/"; do
    echo "Testing: $BASE"
    URL="${BASE}search/?s=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$QUERY'))")"
    RESULT=$(curl -s --max-time 15 "$URL" 2>/dev/null)
    if [ -n "$RESULT" ]; then
        # Check if tracks found
        HAS_TRACKS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print('YES' if any('tracks' in str(v) for v in d.values()) else 'NO')" 2>/dev/null || echo "NO")
        echo "  Has tracks: $HAS_TRACKS"
        if [ "$HAS_TRACKS" = "YES" ]; then
            echo "$RESULT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for k,v in d.items():
    if isinstance(v, dict) and 'items' in v:
        for item in v['items'][:2]:
            title = item.get('title', '')
            artists = [a['name'] for a in item.get('artists', [])]
            video_cover = item.get('album', {}).get('videoCover', '')
            print(f'  Track: {title} - {artists}')
            print(f'  Video Cover ID: {video_cover}')
            if video_cover:
                parts = video_cover.split('-')
                if len(parts) == 5:
                    mp4 = f'https://resources.tidal.com/videos/{parts[0]}/{parts[1]}/{parts[2]}/{parts[3]}/{parts[4]}/1280x1280.mp4'
                    print(f'  MP4 URL: {mp4}')
        break
" 2>/dev/null
        fi
    else
        echo "  No response"
    fi
done

# Test 3: Full canvas_fetcher.py
echo ""
echo "--- 3. canvas_fetcher.py (Full Chain) ---"
if [ -n "$ALBUM" ]; then
    python3 canvas_fetcher.py "$SONG" "$ARTIST" "$ALBUM" | python3 -m json.tool
else
    python3 canvas_fetcher.py "$SONG" "$ARTIST" | python3 -m json.tool
fi

echo ""
echo "=========================================="
