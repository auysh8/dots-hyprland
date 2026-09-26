import os
import sys
import shutil
import sqlite3
import tempfile
import asyncio
import json
import time
import signal
import socket
import logging
from logging.handlers import RotatingFileHandler
from contextlib import asynccontextmanager
import subprocess
import hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from gemini_webapi import GeminiClient
from gemini_webapi.constants import AccountStatus

# Set up logging to both persistent file and stdout
LOG_DIR = os.path.expanduser("~/.local/state/quickshell")
os.makedirs(LOG_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, "gemini_server.log")

logger = logging.getLogger("gemini_server")
logger.setLevel(logging.INFO)

file_handler = RotatingFileHandler(LOG_FILE, maxBytes=5 * 1024 * 1024, backupCount=3, encoding="utf-8")
file_formatter = logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
file_handler.setFormatter(file_formatter)
logger.addHandler(file_handler)

# Safe console handler that ignores BrokenPipeError
class SafeStreamHandler(logging.StreamHandler):
    def emit(self, record):
        try:
            super().emit(record)
        except (BrokenPipeError, OSError):
            pass

console_handler = SafeStreamHandler(sys.stdout)
console_handler.setFormatter(file_formatter)
logger.addHandler(console_handler)

if hasattr(signal, "SIGPIPE"):
    try:
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    except Exception:
        pass

client = None
client_lock = asyncio.Lock()
client_initialized_at = 0.0
last_chrome_cookies_mtime = 0.0
chrome_cookies_path = ""

class ChatRequest(BaseModel):
    prompt: str
    model: str | None = None
    file_path: str | None = None

def get_chrome_password():
    for app in ["chrome", "google-chrome", "chromium"]:
        try:
            res = subprocess.run(["secret-tool", "lookup", "application", app], capture_output=True, text=True, check=True)
            if res.stdout.strip():
                return res.stdout.strip()
        except Exception:
            pass
    return "peanuts"

def decrypt_chrome_cookie(enc_bytes, key):
    if not enc_bytes:
        return ""
    if enc_bytes[:3] in (b"v10", b"v11"):
        enc_bytes = enc_bytes[3:]
    try:
        cipher = Cipher(algorithms.AES(key), modes.CBC(b" " * 16))
        decryptor = cipher.decryptor()
        dec = decryptor.update(enc_bytes) + decryptor.finalize()
        unpad = padding.PKCS7(128).unpadder()
        val = unpad.update(dec) + unpad.finalize()
        # In Chrome Linux v11, the first 32 bytes are a signature/header
        if len(val) > 32 and (val[32:].startswith(b"g.a") or val[32:].startswith(b"sidts-") or val[32:].startswith(b"AK") or val[32:].startswith(b"__")):
            return val[32:].decode("utf-8", errors="replace")
        return val.decode("utf-8", errors="replace")
    except Exception as e:
        logger.debug(f"Chrome cookie decryption error: {e}")
        return ""

def get_chrome_cookies_file():
    possible_paths = [
        os.path.expanduser("~/.config/google-chrome/Default/Cookies"),
        os.path.expanduser("~/.config/chromium/Default/Cookies"),
    ]
    for p in possible_paths:
        if os.path.isfile(p):
            return p
    return None

def extract_chrome_cookies(chrome_path: str) -> dict:
    if not chrome_path or not os.path.exists(chrome_path):
        return {}
    fd, temp_path = tempfile.mkstemp(suffix=".sqlite")
    os.close(fd)
    try:
        shutil.copy2(chrome_path, temp_path)
        conn = sqlite3.connect(temp_path)
        cursor = conn.cursor()
        cursor.execute("""
            SELECT name, encrypted_value 
            FROM cookies 
            WHERE host_key LIKE '%google.com' 
            AND name IN ('__Secure-1PSID', '__Secure-1PSIDTS', '__Secure-1PSIDCC')
            ORDER BY last_access_utc DESC
        """)
        password = get_chrome_password()
        key = hashlib.pbkdf2_hmac("sha1", password.encode("utf-8"), b"saltysalt", 1, 16)
        cookies = {}
        for name, enc in cursor.fetchall():
            if name not in cookies:
                dec = decrypt_chrome_cookie(enc, key)
                if dec:
                    cookies[name] = dec
        conn.close()
        return cookies
    except Exception as e:
        logger.error(f"Failed to read Chrome cookies from {chrome_path}: {e}")
        return {}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

async def get_or_init_client(force_refresh: bool = False, require_authenticated: bool = False):
    global client, client_initialized_at, last_chrome_cookies_mtime, chrome_cookies_path
    async with client_lock:
        now = time.time()
        chrome_path = get_chrome_cookies_file()
        if not chrome_path:
            raise FileNotFoundError("Google Chrome cookies file not found at ~/.config/google-chrome/Default/Cookies")

        chrome_cookies_path = chrome_path
        cookies_changed = False
        try:
            current_mtime = os.path.getmtime(chrome_path)
            if last_chrome_cookies_mtime > 0 and current_mtime > last_chrome_cookies_mtime:
                cookies_changed = True
            last_chrome_cookies_mtime = current_mtime
        except OSError:
            pass

        expired = (now - client_initialized_at) > 1800  # 30 min expiration

        if client is not None and not force_refresh and not cookies_changed and not expired:
            if not require_authenticated or getattr(client, "account_status", None) == AccountStatus.AVAILABLE:
                return client

        if cookies_changed:
            logger.info("Google Chrome cookies updated on disk. Refreshing GeminiClient...")
        elif expired and client is not None:
            logger.info("Client session expired (>30m). Refreshing GeminiClient...")

        if client is not None:
            try:
                await client.close()
            except Exception as close_err:
                logger.debug(f"Error closing old client: {close_err}")
            client = None

        logger.info(f"Extracting cookies exclusively from Google Chrome ({chrome_path})...")
        cookies = extract_chrome_cookies(chrome_path)
        if not cookies or "__Secure-1PSID" not in cookies:
            raise RuntimeError(f"__Secure-1PSID cookie not found in Google Chrome ({chrome_path})")

        new_client = GeminiClient(
            secure_1psid=cookies.get("__Secure-1PSID"),
            secure_1psidts=cookies.get("__Secure-1PSIDTS"),
            secure_1psidcc=cookies.get("__Secure-1PSIDCC"),
            timeout=180,
            watchdog_timeout=120,
        )
        if "__Secure-1PSIDCC" in cookies:
            new_client._cookies.set("__Secure-1PSIDCC", cookies["__Secure-1PSIDCC"], domain=".google.com", secure=True)

        await new_client.init(timeout=180, watchdog_timeout=120)
        status = getattr(new_client, "account_status", None)
        logger.info(f"Google Chrome GeminiClient status: {status}")

        client = new_client
        client_initialized_at = time.time()
        if status == AccountStatus.AVAILABLE:
            logger.info("GeminiClient authenticated successfully using Google Chrome. Status: AVAILABLE")
        else:
            logger.warning(f"Google Chrome session status is {status}. If unauthenticated, visit gemini.google.com in Google Chrome to log in or refresh your session.")
        return client

@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        await get_or_init_client(force_refresh=True)
    except Exception as e:
        logger.error(f"Startup init error: {e}")
    yield
    global client
    if client:
        try:
            await client.close()
        except Exception:
            pass

app = FastAPI(lifespan=lifespan)

ERROR_PATTERNS = [
    "i seem to be encountering an error",
    "i encountered an error doing what you asked",
    "something went wrong",
    "i'm having trouble with that right now",
    "can i try something else for you"
]

def is_gemini_error_text(text: str) -> bool:
    low = text.lower().strip()
    return any(pattern in low for pattern in ERROR_PATTERNS)

@app.post("/chat")
async def chat(request: ChatRequest):
    async def generate():
        temp_file = None
        try:
            files = None
            if request.file_path and os.path.isfile(request.file_path):
                file_path = request.file_path
                if not os.path.splitext(file_path)[1]:
                    with open(file_path, "rb") as f:
                        header = f.read(16)
                    if header[:8] == b'\x89PNG\r\n\x1a\n':
                        ext = ".png"
                    elif header[:3] == b'\xff\xd8\xff':
                        ext = ".jpg"
                    elif header[:6] in (b'GIF87a', b'GIF89a'):
                        ext = ".gif"
                    elif header[:4] == b'RIFF' and header[8:12] == b'WEBP':
                        ext = ".webp"
                    else:
                        ext = ".png"
                    fd, temp_path = tempfile.mkstemp(suffix=ext)
                    os.close(fd)
                    shutil.copy2(file_path, temp_path)
                    file_path = temp_path
                    temp_file = temp_path
                files = [file_path]
                logger.info(f"Attaching file: {file_path}")
            elif request.file_path:
                logger.warning(f"file_path specified but not found: {request.file_path}")

            has_files = bool(files)
            # Try request with automatic retry and cookie refresh if session expired
            for attempt in range(2):
                active_client = await get_or_init_client(
                    force_refresh=(attempt > 0),
                    require_authenticated=has_files
                )
                if not active_client:
                    raise RuntimeError("GeminiClient could not be initialized")

                if has_files and getattr(active_client, "account_status", None) != AccountStatus.AVAILABLE:
                    if attempt == 0:
                        logger.info("Client not authenticated on attempt 0; forcing refresh for file upload...")
                        await asyncio.sleep(0.5)
                        continue
                    err_msg = "Image upload requires an active authenticated Gemini session. Please open Google Chrome and visit gemini.google.com to log in or refresh your session."
                    logger.warning(err_msg)
                    yield f"data: {json.dumps({'error': err_msg})}\n\n"
                    return

                collected_chunks = []
                failed = False
                first_chunk_error = False

                try:
                    target_model = None if request.model in (None, "", "unspecified") else request.model
                    async for chunk in active_client.generate_content_stream(request.prompt, model=target_model, files=files):
                        if hasattr(chunk, 'text_delta') and chunk.text_delta:
                            if not collected_chunks and is_gemini_error_text(chunk.text_delta):
                                first_chunk_error = True
                                break
                            
                            collected_chunks.append(chunk.text_delta)
                            yield f"data: {json.dumps({'text': chunk.text_delta})}\n\n"
                    
                    if first_chunk_error:
                        logger.warning(f"Attempt {attempt + 1}: Gemini returned conversational error text. Refreshing session cookies...")
                        failed = True
                    else:
                        # Completed successfully
                        break

                except Exception as stream_err:
                    logger.error(f"Attempt {attempt + 1} stream error: {stream_err}")
                    failed = True

                if failed:
                    if attempt == 0 and not collected_chunks:
                        logger.info("Retrying request with fresh cookies...")
                        await asyncio.sleep(0.5)
                        continue
                    else:
                        if not collected_chunks:
                            yield f"data: {json.dumps({'error': 'Failed to generate response after session refresh.'})}\n\n"
                        break

        except Exception as e:
            logger.error(f"Setup/Request error: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"
        finally:
            if temp_file and os.path.exists(temp_file):
                os.remove(temp_file)

    return StreamingResponse(generate(), media_type="text/event-stream")

@app.get("/models")
async def list_models():
    try:
        active_client = await get_or_init_client()
        if not active_client:
            return []
        models = active_client.list_models()
        if not models:
            return []
        return [
            {
                "id": m.model_id,
                "name": m.display_name,
                "description": m.description,
                "is_available": m.is_available
            }
            for m in models if m.is_available
        ]
    except Exception as e:
        logger.error(f"list_models error: {e}")
        return []

def free_port(port: int = 8765):
    """Ensure no stale instance is occupying the target port."""
    import subprocess
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(("127.0.0.1", port)) != 0:
                return  # Port is already free
        
        logger.info(f"Port {port} is occupied. Terminating stale process...")
        subprocess.run(["fuser", "-k", f"{port}/tcp"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.5)
    except Exception as e:
        logger.warning(f"Port cleanup check encountered: {e}")

if __name__ == "__main__":
    free_port(8765)
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8765)
