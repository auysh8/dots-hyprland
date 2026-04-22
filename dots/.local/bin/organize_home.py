#!/usr/bin/env python3
import os
import shutil
import hashlib
import time
from pathlib import Path
from datetime import datetime

# --- Configuration ---
SOURCE_DIRS = [
    Path.home(),
    Path.home() / "Downloads",
    Path.home() / "Desktop"
]

CATEGORIES = {
    "Videos": [".mp4", ".mkv", ".avi", ".mov", ".flv", ".wmv", ".webm"],
    "Documents": [".pdf"],
    "Pictures": [".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg"],
    "Music": [".mp3", ".flac", ".wav", ".m4a", ".ogg"],
    "Documents/Archives": [".zip", ".tar.gz", ".tar.xz", ".rar", ".7z"],
    "Documents/ISOs": [".iso", ".img", ".qcow2", ".vmdk"],
    "Documents/Books": [".epub", ".mobi", ".azw3"],
    "Documents/Android/Builds": [".apk", ".aab"]
}

# Directories to NEVER move or scan for project detection
EXCLUDE_DIRS = [
    ".local", ".config", ".cache", "dots-hyprland", "scripts", 
    "Projects", "Music", "Videos", "Pictures", "Documents", 
    "Desktop", "Downloads", "Themes", "icons", ".icons", 
    ".gnupg", ".ssh", ".git", ".npm", ".node-lts", ".cargo", "go"
]

CLEANUP_EXTENSIONS = [".crdownload", ".part"]
CLEANUP_THRESHOLD_DAYS = 7

# --- Helpers ---

def get_file_hash(path):
    """Calculate SHA256 hash of a file."""
    hasher = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            while chunk := f.read(8192):
                hasher.update(chunk)
        return hasher.hexdigest()
    except Exception as e:
        return None

def get_unique_path(path):
    """Avoid overwriting by adding a numeric suffix."""
    if not path.exists():
        return path
    counter = 1
    while True:
        new_path = path.parent / f"{path.stem} ({counter}){path.suffix}"
        if not new_path.exists():
            return new_path
        counter += 1

def cleanup_old_files():
    """Delete partial downloads and empty folders older than threshold."""
    print(f"--- Cleanup Phase ---")
    now = time.time()
    threshold = CLEANUP_THRESHOLD_DAYS * 86400

    for source_dir in SOURCE_DIRS:
        if not source_dir.exists(): continue
        for item in source_dir.rglob("*"):
            try:
                if item.is_file() and item.suffix.lower() in CLEANUP_EXTENSIONS:
                    if now - item.stat().st_mtime > threshold:
                        print(f"  Deleting old partial download: {item.name}")
                        item.unlink()
                if item.is_dir() and not any(item.iterdir()):
                    if now - item.stat().st_mtime > threshold:
                        print(f"  Deleting old empty folder: {item.name}")
                        item.rmdir()
            except: continue

def handle_special_folders():
    """Handle Screenshots, Themes, and Project Detection."""
    print(f"--- Special Folder Organization ---")
    home = Path.home()

    # 1. Screenshots Organizer
    ss_dir = home / "Screenshots"
    if ss_dir.exists() and ss_dir.is_dir():
        for ss in ss_dir.iterdir():
            if ss.is_file() and not ss.name.startswith('.'):
                mtime = datetime.fromtimestamp(ss.stat().st_mtime)
                dest = home / "Pictures" / "Screenshots" / str(mtime.year) / mtime.strftime("%B")
                dest.mkdir(parents=True, exist_ok=True)
                print(f"  Screenshot: {ss.name} -> Pictures/Screenshots/")
                shutil.move(str(ss), str(get_unique_path(dest / ss.name)))

    # 2. Themes Consolidator
    theme_dest = home / "Themes"
    for item in home.iterdir():
        if item.is_dir() and item.name.endswith("-themes-collection") and item.name not in EXCLUDE_DIRS:
            theme_dest.mkdir(exist_ok=True)
            print(f"  Theme: {item.name} -> Themes/")
            # Using shutil.move for directories
            target = get_unique_path(theme_dest / item.name)
            shutil.move(str(item), str(target))

    # 3. Project Detector
    project_dest = home / "Projects"
    for item in home.iterdir():
        if item.is_dir() and not item.name.startswith('.') and item.name not in EXCLUDE_DIRS:
            # Check for project indicators
            if (item / ".git").exists() or (item / "package.json").exists():
                project_dest.mkdir(exist_ok=True)
                print(f"  Project: {item.name} -> Projects/")
                target = get_unique_path(project_dest / item.name)
                shutil.move(str(item), str(target))

    # 4. Script Tidy (Loose files in ~)
    script_dest = home / "scripts"
    for item in home.iterdir():
        if item.is_file() and item.suffix.lower() in [".py", ".sh"] and item.name not in ["organize_home.py"]:
            script_dest.mkdir(exist_ok=True)
            print(f"  Script: {item.name} -> scripts/")
            shutil.move(str(item), str(get_unique_path(script_dest / item.name)))

def organize():
    print("--- Starting Advanced Home Organization ---")
    
    cleanup_old_files()
    handle_special_folders()

    moved_count = 0
    deleted_duplicates = 0
    category_hashes = {}

    for category, extensions in CATEGORIES.items():
        dest_root = Path.home() / category
        dest_root.mkdir(parents=True, exist_ok=True)
        
        # Index existing files (subset for performance if needed, but keeping full for now)
        hashes = set()
        for file_path in dest_root.rglob("*"):
            if file_path.is_file():
                f_hash = get_file_hash(file_path)
                if f_hash: hashes.add(f_hash)
        category_hashes[category] = hashes

        for source_dir in SOURCE_DIRS:
            if not source_dir.exists(): continue
            for item in source_dir.iterdir():
                if item.is_file() and not item.name.startswith('.') and item.suffix.lower() in extensions:
                    if str(dest_root) in str(item.resolve()): continue

                    source_hash = get_file_hash(item)
                    if not source_hash: continue

                    if source_hash in category_hashes[category]:
                        print(f"  Duplicate: {item.name} -> Deleted.")
                        item.unlink()
                        deleted_duplicates += 1
                        continue

                    mtime = datetime.fromtimestamp(item.stat().st_mtime)
                    date_path = dest_root / str(mtime.year) / mtime.strftime("%B")
                    date_path.mkdir(parents=True, exist_ok=True)
                    
                    try:
                        print(f"  File: {item.name} -> {category}/")
                        shutil.move(str(item), str(get_unique_path(date_path / item.name)))
                        category_hashes[category].add(source_hash)
                        moved_count += 1
                    except Exception as e:
                        print(f"  Error: {item.name} {e}")

    print(f"--- Summary ---")
    print(f"Files organized: {moved_count}")
    print(f"Duplicates removed: {deleted_duplicates}")
    print(f"--- Done ---")

if __name__ == "__main__":
    organize()
