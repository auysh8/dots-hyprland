from ytmusicapi import YTMusic
import os
import json

script_dir = "/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/"
headers_path = os.path.join(script_dir, "headers_auth.json")
ytm = YTMusic(headers_path)

print("Fetching watch playlist for gm-Y9idMMQ4...")
try:
    data = ytm.get_watch_playlist(videoId="gm-Y9idMMQ4", limit=12)
    print("Success! Tracks found:", len(data.get('tracks', [])))
except Exception as e:
    print(f"Error: {e}")

print("\nFetching watch playlist for wqlTrBCNRiY...")
try:
    data = ytm.get_watch_playlist(videoId="wqlTrBCNRiY", limit=12)
    print("Success! Tracks found:", len(data.get('tracks', [])))
except Exception as e:
    print(f"Error: {e}")
