import os
import json

def extract(target_file_path: str):
    """
    Extracts YouTube cookies from installed browsers and saves them to
    target_file_path (usually headers_auth.json) for ytmusicapi.
    
    Returns:
        {"success": bool, "cookies_found": int, "error": str/None}
    """
    try:
        import browser_cookie3
    except ImportError:
        return {
            "success": False,
            "error": "browser_cookie3 is not installed in the Python virtual environment. Please run 'pip install browser-cookie3' in the musicLayer/venv."
        }

    try:
        browsers = [
            browser_cookie3.firefox,
            browser_cookie3.chrome,
            browser_cookie3.brave,
            browser_cookie3.edge,
            browser_cookie3.chromium,
            browser_cookie3.opera,
            browser_cookie3.vivaldi
        ]
        
        cookies = []
        for browser_fn in browsers:
            try:
                cj = browser_fn(domain_name=".youtube.com")
                cookies.extend(list(cj))
            except Exception:
                pass
        
        # Deduplicate cookies by name
        unique_cookies = {}
        for cookie in cookies:
            unique_cookies[cookie.name] = cookie
        cookies = list(unique_cookies.values())
        
        cookie_parts = []
        auth_cookie_found = False
        for cookie in cookies:
            cookie_parts.append(f"{cookie.name}={cookie.value}")
            if cookie.name in ("SAPISID", "SSID", "APISID", "HSID", "SID"):
                auth_cookie_found = True
        
        cookie_string = "; ".join(cookie_parts)
        
        if not cookie_string:
            return {"success": False, "error": "No YouTube cookies found in any installed browsers."}
            
        if not auth_cookie_found:
             return {"success": False, "error": "YouTube cookies found, but no login session cookies exist. Please log in to YouTube/YouTube Music in your browser first."}
             
        try:
            from ytmusicapi.helpers import get_authorization, sapisid_from_cookie
            origin = "https://music.youtube.com"
            sapisid = sapisid_from_cookie(cookie_string)
            auth_header = get_authorization(sapisid + " " + origin)
        except Exception as e:
            return {"success": False, "error": f"Failed to compute authorization header: {e}"}
        
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36",
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.5",
            "Content-Type": "application/json",
            "X-Origin": origin,
            "Authorization": auth_header,
            "Cookie": cookie_string
        }
        
        with open(target_file_path, "w", encoding="utf-8") as f:
            json.dump(headers, f, indent=4)
            
        return {"success": True, "cookies_found": len(cookies), "error": None}
    except Exception as e:
        return {"success": False, "error": str(e)}
