import os
import shutil
import sqlite3
import tempfile
import asyncio
import json
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from gemini_webapi import GeminiClient

app = FastAPI()
client = None
client_lock = asyncio.Lock()

class ChatRequest(BaseModel):
    prompt: str
    model: str | None = None
    file_path: str | None = None

def extract_cookies():
    possible_bases = [
        os.path.expanduser("~/.config/zen"),
        os.path.expanduser("~/.zen")
    ]
    
    candidates = []
    for base in possible_bases:
        if not os.path.exists(base):
            continue
        for root, dirs, files in os.walk(base):
            if "cookies.sqlite" in files:
                candidates.append(os.path.join(root, "cookies.sqlite"))
                
    if not candidates:
        raise FileNotFoundError(f"Cookies file not found in Zen browser profile paths ({possible_bases})")

    # Sort profiles so the most recently active cookies.sqlite is evaluated first
    candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)

    for profile_path in candidates:
        fd, temp_path = tempfile.mkstemp(suffix=".sqlite")
        os.close(fd)
        
        try:
            shutil.copy2(profile_path, temp_path)
            
            conn = sqlite3.connect(temp_path)
            cursor = conn.cursor()
            
            # Query for Gemini cookies
            cursor.execute("""
                SELECT name, value 
                FROM moz_cookies 
                WHERE host LIKE '%google.com' 
                AND name IN ('__Secure-1PSID', '__Secure-1PSIDTS', '__Secure-1PSIDCC')
            """)
            
            cookies = {row[0]: row[1] for row in cursor.fetchall()}
            conn.close()
            
            if '__Secure-1PSID' in cookies:
                return cookies
        except Exception as e:
            print(f"[Gemini Server] Failed to read cookies from {profile_path}: {e}")
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)

    return {}

async def get_or_init_client(force_refresh: bool = False):
    global client
    async with client_lock:
        if client is not None and not force_refresh:
            return client
        
        try:
            cookies = extract_cookies()
            if '__Secure-1PSID' not in cookies:
                print("[Gemini Server] Warning: __Secure-1PSID cookie not found in browser profiles.")
                
            new_client = GeminiClient(
                secure_1psid=cookies.get('__Secure-1PSID'),
                secure_1psidts=cookies.get('__Secure-1PSIDTS'),
                secure_1psidcc=cookies.get('__Secure-1PSIDCC')
            )
            await new_client.init(timeout=60)
            client = new_client
            print("[Gemini Server] GeminiClient initialized/refreshed successfully.")
            return client
        except Exception as e:
            print(f"[Gemini Server] Failed to initialize GeminiClient: {e}")
            if client is not None and not force_refresh:
                return client
            raise e

@app.on_event("startup")
async def startup_event():
    try:
        await get_or_init_client(force_refresh=True)
    except Exception as e:
        print(f"[Gemini Server] Startup init error: {e}")

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
                print(f"[Gemini Server] Attaching file: {file_path}")
            elif request.file_path:
                print(f"[Gemini Server] Warning: file_path specified but not found: {request.file_path}")

            # Try request with automatic retry and cookie refresh if session expired
            for attempt in range(2):
                active_client = await get_or_init_client(force_refresh=(attempt > 0))
                if not active_client:
                    raise RuntimeError("GeminiClient could not be initialized")

                collected_chunks = []
                failed = False
                first_chunk_error = False

                try:
                    async for chunk in active_client.generate_content_stream(request.prompt, model=request.model or "unspecified", files=files):
                        if hasattr(chunk, 'text_delta') and chunk.text_delta:
                            # If this is the start of the response and it matches a canned error sentence
                            if not collected_chunks and is_gemini_error_text(chunk.text_delta):
                                first_chunk_error = True
                                break
                            
                            collected_chunks.append(chunk.text_delta)
                            yield f"data: {json.dumps({'text': chunk.text_delta})}\n\n"
                    
                    if first_chunk_error:
                        print(f"[Gemini Server] Attempt {attempt + 1}: Gemini returned conversational error text. Refreshing session cookies...")
                        failed = True
                    else:
                        # Completed successfully
                        break

                except Exception as stream_err:
                    print(f"[Gemini Server] Attempt {attempt + 1} stream error: {stream_err}")
                    failed = True

                if failed:
                    if attempt == 0:
                        print("[Gemini Server] Retrying request with fresh cookies...")
                        await asyncio.sleep(0.5)
                        continue
                    else:
                        yield f"data: {json.dumps({'error': 'Failed to generate response after session refresh.'})}\n\n"
                        break

        except Exception as e:
            print(f"[Gemini Server] Setup/Request error: {e}")
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
        print(f"[Gemini Server] list_models error: {e}")
        return []

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8765)
