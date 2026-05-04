#!/usr/bin/env python3
import argparse
import fcntl
import hashlib
import logging
import shutil
import sys
import time
import tomllib
from contextlib import contextmanager
from datetime import datetime
from logging.handlers import RotatingFileHandler
from pathlib import Path

HOME = Path.home()
CONFIG_FILE = HOME / ".config" / "organize-home" / "config.toml"
STATE_DIR = HOME / ".local" / "state" / "organize-home"
LOG_FILE = STATE_DIR / "organize.log"
LOCK_FILE = STATE_DIR / "organize.lock"

DEFAULT_SOURCE_DIRS = [
    "~",
    "~/Downloads",
    "~/Desktop",
    "~/Documents",
]

DEFAULT_CATEGORIES = {
    "Videos": [".mp4", ".mkv", ".avi", ".mov", ".flv", ".wmv", ".webm"],
    "Documents": [".pdf", ".doc", ".docx", ".odt", ".txt", ".md"],
    "Documents/Spreadsheets": [".xls", ".xlsx", ".ods", ".csv"],
    "Documents/Presentations": [".ppt", ".pptx", ".odp"],
    "Pictures": [".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg", ".avif"],
    "Music": [".mp3", ".flac", ".wav", ".m4a", ".ogg", ".opus"],
    "Documents/Archives": [".zip", ".tar.gz", ".tar.xz", ".tar.bz2", ".rar", ".7z"],
    "Documents/ISOs": [".iso", ".img", ".qcow2", ".vmdk"],
    "Documents/Books": [".epub", ".mobi", ".azw3"],
    "Documents/Android/Builds": [".apk", ".aab"],
    "Documents/Patches": [".rvp"],
}

DEFAULT_EXCLUDE_DIRS = {
    ".local",
    ".config",
    ".cache",
    ".gnupg",
    ".ssh",
    ".git",
    ".npm",
    ".node-lts",
    ".cargo",
    "go",
    "dots-hyprland",
    "scripts",
    "Projects",
    "Music",
    "Videos",
    "Pictures",
    "Documents",
    "Desktop",
    "Downloads",
    "Themes",
    "icons",
    ".icons",
}

DEFAULT_PROJECT_MARKERS = [
    ".git",
    "package.json",
    "pyproject.toml",
    "Cargo.toml",
    "go.mod",
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "settings.gradle.kts",
    "pom.xml",
    "CMakeLists.txt",
]

DEFAULT_CLEANUP_DIRS = [
    "~/Downloads",
    "~/Desktop",
]

DEFAULT_EMPTY_DIR_CLEANUP_ROOTS = [
    "~/Downloads",
    "~/Desktop",
    "~/Documents/2026",
    "~/Documents/Android",
    "~/Documents/Archives",
    "~/Documents/Books",
    "~/Documents/ISOs",
    "~/Documents/Patches",
    "~/Documents/Presentations",
    "~/Documents/Spreadsheets",
]

DEFAULT_PROTECTED_EMPTY_DIRS = [
    "~",
    "~/Downloads",
    "~/Desktop",
    "~/Documents",
]

SOURCE_DIRS = []
CATEGORIES = {}
EXCLUDE_DIRS = set()
PROJECT_MARKERS = []
CLEANUP_DIRS = []
EMPTY_DIR_CLEANUP_ROOTS = []
PROTECTED_EMPTY_DIRS = set()
CLEANUP_EXTENSIONS = [".crdownload", ".part"]
CLEANUP_THRESHOLD_DAYS = 7
DUPLICATE_DIR = HOME / "Documents" / "Duplicates"
RECENT_FILE_DELAY_SECONDS = 120
STABLE_CHECK_INTERVAL_SECONDS = 2


def expand_path(value):
    return Path(value).expanduser()


def normalize_extensions(extensions):
    normalized = []
    for extension in extensions:
        extension = extension.lower()
        normalized.append(extension if extension.startswith(".") else f".{extension}")
    return normalized


def read_config():
    if not CONFIG_FILE.exists():
        return {}

    try:
        with CONFIG_FILE.open("rb") as file:
            return tomllib.load(file)
    except (OSError, tomllib.TOMLDecodeError) as error:
        logging.warning("Could not read config %s: %s", CONFIG_FILE, error)
        return {}


def load_settings():
    global SOURCE_DIRS
    global CATEGORIES
    global EXCLUDE_DIRS
    global PROJECT_MARKERS
    global CLEANUP_DIRS
    global EMPTY_DIR_CLEANUP_ROOTS
    global PROTECTED_EMPTY_DIRS
    global CLEANUP_EXTENSIONS
    global CLEANUP_THRESHOLD_DAYS
    global DUPLICATE_DIR
    global RECENT_FILE_DELAY_SECONDS
    global STABLE_CHECK_INTERVAL_SECONDS

    config = read_config()
    general = config.get("general", {})
    cleanup = config.get("cleanup", {})

    SOURCE_DIRS = [expand_path(path) for path in general.get("source_dirs", DEFAULT_SOURCE_DIRS)]
    CATEGORIES = {
        category: normalize_extensions(extensions)
        for category, extensions in config.get("categories", DEFAULT_CATEGORIES).items()
    }
    EXCLUDE_DIRS = set(general.get("exclude_dirs", sorted(DEFAULT_EXCLUDE_DIRS)))
    PROJECT_MARKERS = list(general.get("project_markers", DEFAULT_PROJECT_MARKERS))

    CLEANUP_DIRS = [expand_path(path) for path in cleanup.get("cleanup_dirs", DEFAULT_CLEANUP_DIRS)]
    EMPTY_DIR_CLEANUP_ROOTS = [
        expand_path(path)
        for path in cleanup.get("empty_dir_cleanup_roots", DEFAULT_EMPTY_DIR_CLEANUP_ROOTS)
    ]
    PROTECTED_EMPTY_DIRS = {
        expand_path(path).resolve()
        for path in cleanup.get("protected_empty_dirs", DEFAULT_PROTECTED_EMPTY_DIRS)
    }
    CLEANUP_EXTENSIONS = normalize_extensions(cleanup.get("partial_extensions", [".crdownload", ".part"]))
    CLEANUP_THRESHOLD_DAYS = int(cleanup.get("partial_cleanup_days", 7))
    DUPLICATE_DIR = expand_path(cleanup.get("duplicate_dir", "~/Documents/Duplicates"))
    RECENT_FILE_DELAY_SECONDS = int(cleanup.get("recent_file_delay_seconds", 120))
    STABLE_CHECK_INTERVAL_SECONDS = int(cleanup.get("stable_check_interval_seconds", 2))


def setup_logging(verbose=False):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    handlers = [
        RotatingFileHandler(LOG_FILE, maxBytes=1_000_000, backupCount=5),
        logging.StreamHandler(sys.stdout),
    ]
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s %(levelname)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=handlers,
    )


@contextmanager
def single_instance():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    lock_handle = LOCK_FILE.open("w")
    try:
        fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        logging.info("Another organize-home run is already active; skipping this run.")
        lock_handle.close()
        yield False
        return

    try:
        lock_handle.write(str(os_getpid()))
        lock_handle.flush()
        yield True
    finally:
        fcntl.flock(lock_handle, fcntl.LOCK_UN)
        lock_handle.close()


def os_getpid():
    try:
        import os

        return os.getpid()
    except OSError:
        return ""


def file_hash(path):
    hasher = hashlib.sha256()
    try:
        with path.open("rb") as file:
            for chunk in iter(lambda: file.read(1024 * 1024), b""):
                hasher.update(chunk)
        return hasher.hexdigest()
    except OSError as error:
        logging.warning("Could not hash %s: %s", path, error)
        return None


def unique_path(path):
    if not path.exists():
        return path

    counter = 1
    suffix = "".join(path.suffixes)
    stem = path.name[: -len(suffix)] if suffix else path.name
    while True:
        candidate = path.with_name(f"{stem} ({counter}){suffix}")
        if not candidate.exists():
            return candidate
        counter += 1


def has_extension(path, extensions):
    name = path.name.lower()
    return any(name.endswith(extension) for extension in extensions)


def is_inside(path, directory):
    try:
        path.resolve().relative_to(directory.resolve())
        return True
    except ValueError:
        return False
    except OSError:
        return False


def is_recent(path):
    if RECENT_FILE_DELAY_SECONDS <= 0:
        return False

    try:
        return time.time() - path.stat().st_mtime < RECENT_FILE_DELAY_SECONDS
    except OSError as error:
        logging.warning("Could not stat %s: %s", path, error)
        return True


def is_stable_file(path, dry_run=False):
    if dry_run or STABLE_CHECK_INTERVAL_SECONDS <= 0:
        return True

    try:
        first = path.stat()
        time.sleep(STABLE_CHECK_INTERVAL_SECONDS)
        second = path.stat()
    except OSError as error:
        logging.warning("Could not stability-check %s: %s", path, error)
        return False

    if first.st_size != second.st_size or first.st_mtime_ns != second.st_mtime_ns:
        logging.info("Skipping changing file: %s", path)
        return False

    return True


def move_path(source, target, dry_run=False):
    target = unique_path(target)
    logging.info("%s -> %s", source, target)
    if dry_run:
        return target

    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(target))
    return target


def delete_or_quarantine_duplicate(path, dry_run=False):
    target = DUPLICATE_DIR / datetime.now().strftime("%Y-%m-%d") / path.name
    logging.info("Duplicate quarantined: %s -> %s", path, target)
    if dry_run:
        return

    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), str(unique_path(target)))


def cleanup_old_files(dry_run=False):
    logging.info("--- Cleanup phase ---")
    now = time.time()
    threshold = CLEANUP_THRESHOLD_DAYS * 86400

    for source_dir in CLEANUP_DIRS:
        if not source_dir.exists():
            continue

        for item in source_dir.rglob("*"):
            try:
                age = now - item.stat().st_mtime
                if item.is_file() and item.suffix.lower() in CLEANUP_EXTENSIONS and age > threshold:
                    logging.info("Deleting old partial download: %s", item)
                    if not dry_run:
                        item.unlink()
                elif item.is_dir() and age > threshold and not any(item.iterdir()):
                    logging.info("Deleting old empty folder: %s", item)
                    if not dry_run:
                        item.rmdir()
            except OSError as error:
                logging.warning("Cleanup skipped %s: %s", item, error)


def remove_empty_folders(dry_run=False):
    removed_count = 0

    for root in EMPTY_DIR_CLEANUP_ROOTS:
        if not root.exists() or not root.is_dir():
            continue

        directories = [root]
        directories.extend(path for path in root.rglob("*") if path.is_dir())
        for directory in sorted(directories, key=lambda path: len(path.parts), reverse=True):
            try:
                resolved_directory = directory.resolve()
            except OSError as error:
                logging.warning("Empty folder cleanup skipped %s: %s", directory, error)
                continue

            if resolved_directory in PROTECTED_EMPTY_DIRS:
                continue

            try:
                if any(directory.iterdir()):
                    continue
                logging.info("Removing empty folder: %s", directory)
                if not dry_run:
                    directory.rmdir()
                removed_count += 1
            except OSError as error:
                logging.warning("Empty folder cleanup skipped %s: %s", directory, error)

    return removed_count


def organize_screenshots(dry_run=False):
    screenshots_dir = HOME / "Screenshots"
    if not screenshots_dir.is_dir():
        return

    for screenshot in screenshots_dir.iterdir():
        if screenshot.is_file() and not screenshot.name.startswith("."):
            if is_recent(screenshot) or not is_stable_file(screenshot, dry_run):
                continue
            mtime = datetime.fromtimestamp(screenshot.stat().st_mtime)
            target = HOME / "Pictures" / "Screenshots" / str(mtime.year) / mtime.strftime("%B") / screenshot.name
            move_path(screenshot, target, dry_run)


def is_project_directory(path):
    return any((path / marker).exists() for marker in PROJECT_MARKERS)


def organize_special_folders(dry_run=False):
    logging.info("--- Special folder organization ---")
    organize_screenshots(dry_run)

    themes_dir = HOME / "Themes"
    projects_dir = HOME / "Projects"
    scripts_dir = HOME / "scripts"

    for item in HOME.iterdir():
        if item.is_dir() and item.name.endswith("-themes-collection") and item.name not in EXCLUDE_DIRS:
            move_path(item, themes_dir / item.name, dry_run)

    for item in HOME.iterdir():
        if item.is_dir() and not item.name.startswith(".") and item.name not in EXCLUDE_DIRS:
            if is_project_directory(item):
                move_path(item, projects_dir / item.name, dry_run)

    for item in HOME.iterdir():
        if item.is_file() and has_extension(item, [".py", ".sh"]) and item.name != "organize_home.py":
            if is_recent(item) or not is_stable_file(item, dry_run):
                continue
            move_path(item, scripts_dir / item.name, dry_run)


def index_category_sizes(destination):
    sizes = {}
    if not destination.exists():
        return sizes

    for path in destination.rglob("*"):
        try:
            if path.is_file():
                sizes.setdefault(path.stat().st_size, []).append(path)
        except OSError as error:
            logging.warning("Could not stat %s: %s", path, error)
    return sizes


def has_duplicate(candidate, destination_size_index):
    try:
        same_size_paths = destination_size_index.get(candidate.stat().st_size, [])
        candidate_path = candidate.resolve()
    except OSError as error:
        logging.warning("Could not stat %s: %s", candidate, error)
        return False

    if not same_size_paths:
        return False

    candidate_hash = file_hash(candidate)
    if not candidate_hash:
        return False

    for existing_path in same_size_paths:
        try:
            if existing_path.resolve() == candidate_path:
                continue
        except OSError:
            continue

        existing_hash = file_hash(existing_path)
        if existing_hash and existing_hash == candidate_hash:
            return True

    return False


def collect_candidates(destination_root, extensions):
    candidates = []
    for source_dir in SOURCE_DIRS:
        if not source_dir.exists():
            continue

        for item in source_dir.iterdir():
            if not item.is_file() or item.name.startswith("."):
                continue
            if not has_extension(item, extensions):
                continue
            if item.parent != destination_root and is_inside(item, destination_root):
                continue
            if is_recent(item):
                logging.info("Skipping recent file: %s", item)
                continue
            candidates.append(item)

    return candidates


def organize_files(dry_run=False):
    moved_count = 0
    duplicate_count = 0

    for category, extensions in CATEGORIES.items():
        destination_root = HOME / category
        candidates = collect_candidates(destination_root, extensions)

        if not candidates:
            continue

        destination_size_index = index_category_sizes(destination_root)

        for item in candidates:
            if not is_stable_file(item, dry_run):
                continue

            if has_duplicate(item, destination_size_index):
                delete_or_quarantine_duplicate(item, dry_run)
                duplicate_count += 1
                continue

            mtime = datetime.fromtimestamp(item.stat().st_mtime)
            target = destination_root / str(mtime.year) / mtime.strftime("%B") / item.name
            moved_path = move_path(item, target, dry_run)
            if not dry_run:
                try:
                    destination_size_index.setdefault(moved_path.stat().st_size, []).append(moved_path)
                except OSError as error:
                    logging.warning("Could not stat moved file %s: %s", moved_path, error)
            moved_count += 1

    return moved_count, duplicate_count


def organize(dry_run=False):
    logging.info("--- Starting home organization%s ---", " (dry run)" if dry_run else "")
    cleanup_old_files(dry_run)
    organize_special_folders(dry_run)
    moved_count, duplicate_count = organize_files(dry_run)
    empty_folder_count = remove_empty_folders(dry_run)
    logging.info("--- Summary ---")
    logging.info("Files organized: %s", moved_count)
    logging.info("Duplicates quarantined: %s", duplicate_count)
    logging.info("Empty folders removed: %s", empty_folder_count)
    logging.info("--- Done ---")


def parse_args():
    parser = argparse.ArgumentParser(description="Organize loose files in home, Downloads, Desktop, and Documents.")
    parser.add_argument("--dry-run", action="store_true", help="Log planned changes without moving or deleting anything.")
    parser.add_argument("--verbose", action="store_true", help="Enable debug logging.")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    setup_logging(args.verbose)
    load_settings()
    with single_instance() as acquired:
        if acquired:
            organize(args.dry_run)
