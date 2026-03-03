#!/usr/bin/env python3
"""
Extract YouTube Music auth headers from Zen browser (Firefox-based) cookie database.
Only includes essential auth cookies to keep request size small.
Outputs JSON result to stdout for integration with music_backend.py.
"""
import json, os, sys, shutil, sqlite3, tempfile, hashlib, time
from pathlib import Path

ZEN_PROFILES_INI = Path.home() / ".zen/profiles.ini"
OUTPUT = Path.home() / "dots-hyprland/dots/.config/quickshell/ii/musicLayer/headers_auth.json"

# Essential auth cookies for YouTube Music
ESSENTIAL_NAMES = {
    'SID', 'HSID', 'SSID', 'APISID', 'SAPISID',
    '__Secure-1PSID', '__Secure-3PSID',
    '__Secure-1PAPISID', '__Secure-3PAPISID',
    '__Secure-1PSIDTS', '__Secure-3PSIDTS',
    '__Secure-1PSIDCC', '__Secure-3PSIDCC',
    'SIDCC',
    'LOGIN_INFO', 'PREF', 'YSC', 'VISITOR_INFO1_LIVE',
    'VISITOR_PRIVACY_METADATA', 'SOCS',
    '__Secure-YEC', 'CONSISTENCY',
}

def sha1(s):
    return hashlib.sha1(s.encode()).hexdigest()

def find_zen_cookie_db():
    """Find the Zen browser cookie database."""
    zen_dir = Path.home() / ".zen"
    
    if not zen_dir.exists():
        return None
    
    # Try profiles.ini
    ini = zen_dir / "profiles.ini"
    if ini.exists():
        import configparser
        config = configparser.ConfigParser()
        config.read(ini)
        
        for section in config.sections():
            if section.startswith("Profile") or section.startswith("Install"):
                path = config.get(section, "Path", fallback=None)
                if path:
                    candidate = zen_dir / path / "cookies.sqlite"
                    if candidate.exists():
                        return candidate
    
    # Fallback: search
    for p in zen_dir.glob("*/cookies.sqlite"):
        return p
    
    return None

def find_firefox_cookie_db():
    """Fallback: find Firefox cookie database."""
    ff_dir = Path.home() / ".mozilla/firefox"
    if not ff_dir.exists():
        return None
    
    for p in ff_dir.glob("*.default*/cookies.sqlite"):
        return p
    for p in ff_dir.glob("*/cookies.sqlite"):
        return p
    
    return None

def extract(output_path=None):
    """Extract cookies and build headers_auth.json. Returns dict with status."""
    if output_path is None:
        output_path = OUTPUT
    else:
        output_path = Path(output_path)
    
    # Find cookie database
    cookie_db = find_zen_cookie_db() or find_firefox_cookie_db()
    
    if not cookie_db:
        return {"success": False, "error": "No Zen or Firefox cookie database found"}
    
    tmp_db = tempfile.mktemp(suffix=".sqlite")
    shutil.copy2(cookie_db, tmp_db)
    
    try:
        conn = sqlite3.connect(tmp_db)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT name, value, host FROM moz_cookies
            WHERE (host LIKE '%youtube.com' OR host LIKE '%google.com')
        """)
        
        # Prefer .youtube.com cookies over .google.com
        cookies_by_name = {}
        for name, value, host in cursor.fetchall():
            if not value or name not in ESSENTIAL_NAMES:
                continue
            priority = 1 if 'youtube.com' in host else 2
            existing = cookies_by_name.get(name)
            if not existing or priority < existing[2]:
                cookies_by_name[name] = (value, host, priority)
        
        conn.close()
        
        cookies = {name: val[0] for name, val in cookies_by_name.items()}
        
        if not cookies:
            return {"success": False, "error": "No YouTube cookies found in browser"}
        
        sapisid = cookies.get('SAPISID') or cookies.get('__Secure-3PAPISID')
        if not sapisid:
            return {"success": False, "error": "Not logged into YouTube Music in browser"}
        
        # Generate SAPISIDHASH
        origin = "https://music.youtube.com"
        timestamp = str(int(time.time()))
        sapisid_hash = sha1(f"{timestamp} {sapisid} {origin}")
        authorization = f"SAPISIDHASH {timestamp}_{sapisid_hash}"
        
        cookie_str = "; ".join(f"{k}={v}" for k, v in cookies.items())
        
        headers = {
            "accept": "*/*",
            "accept-language": "en-US,en;q=0.9",
            "authorization": authorization,
            "content-type": "application/json",
            "cookie": cookie_str,
            "origin": origin,
            "referer": "https://music.youtube.com/",
            "user-agent": "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
            "x-origin": origin,
            "x-goog-authuser": "0"
        }
        
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w') as f:
            json.dump(headers, f, indent=2)
        
        return {
            "success": True, 
            "cookies_found": len(cookies),
            "path": str(output_path)
        }
        
    finally:
        if os.path.exists(tmp_db):
            os.remove(tmp_db)


if __name__ == "__main__":
    result = extract()
    print(json.dumps(result))
