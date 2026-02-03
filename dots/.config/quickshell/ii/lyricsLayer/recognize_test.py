#!/usr/bin/env python3
import subprocess
import sys
import os
import json
import time

def main():
    print("[Test] Starting recognition test (via SongRec)...", file=sys.stderr)
    
    # 1. Get Default Monitor Source
    try:
        pactl = subprocess.run(["pactl", "get-default-sink"], capture_output=True, text=True)
        if pactl.returncode != 0:
            print("[Error] Could not get default sink via pactl", file=sys.stderr)
            return
            
        default_sink = pactl.stdout.strip()
        monitor_source = f"{default_sink}.monitor"
        print(f"[Test] Recording from: {monitor_source}", file=sys.stderr)
        
    except Exception as e:
        print(f"[Error] Audio setup failed: {e}", file=sys.stderr)
        return

    # 2. Record 5 seconds of audio
    filename = "snippet.ogg"
    if os.path.exists(filename):
        os.remove(filename)
        
    try:
        # ffmpeg command to record from pulse monitor
        cmd = [
            "ffmpeg", "-y", 
            "-f", "pulse", "-i", monitor_source,
            "-t", "5",
            "-ac", "1",
            "-ar", "44100",
            "-vn", 
            "-c:a", "libvorbis",
            "-loglevel", "error", # quiet
            filename
        ]
        
        print("[Test] Recording 5s clip...", file=sys.stderr)
        subprocess.run(cmd, check=True)
        
    except subprocess.CalledProcessError as e:
        print(f"[Error] FFmpeg recording failed.", file=sys.stderr)
        return

    # 3. Recognize using SongRec
    print("[Test] Sending to SongRec...", file=sys.stderr)
    try:
        # songrec audio-file-to-recognized-song <file>
        result = subprocess.run(
            ["songrec", "audio-file-to-recognized-song", filename],
            capture_output=True, text=True
        )
        
        if result.returncode != 0:
            print(f"[Error] SongRec failed: {result.stderr}", file=sys.stderr)
            return
            
        # Output is likely JSON
        try:
            data = json.loads(result.stdout)
            track = data.get("track", {})
            
            if track:
                title = track.get("title")
                subtitle = track.get("subtitle")
                url = track.get("url")
                
                print("\n=== MATCH FOUND ===")
                print(f"Title:    {title}")
                print(f"Artist:   {subtitle}")
                print(f"Link:     {url}")
                print("===================\n")
            else:
                print("\n[Result] No match found directly in track object.")
                print(f"Raw: {data}")
                
        except json.JSONDecodeError:
            print(f"[Result] Could not parse JSON. Output:\n{result.stdout}")
            
    except Exception as e:
        print(f"[Error] Recognition failed: {e}", file=sys.stderr)
    
    # Cleanup
    if os.path.exists(filename):
        os.remove(filename)

if __name__ == "__main__":
    main()
