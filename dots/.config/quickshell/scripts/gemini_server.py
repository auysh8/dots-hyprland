import os
import shutil
import sqlite3
import tempfile
import asyncio
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from gemini_webapi import GeminiClient

app = FastAPI()
client = None

class ChatRequest(BaseModel):
    prompt: str
    model: str | None = None
    file_path: str | None = None

def extract_cookies():
    # Path to Zen browser default profile
    profile_path = os.path.expanduser("~/.zen/yem0tzbi.Default (release)/cookies.sqlite")
    
    if not os.path.exists(profile_path):
        raise FileNotFoundError(f"Cookies file not found at {profile_path}")

    # Copy to temp file to avoid locking issues
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
        
        return cookies
    finally:
        os.remove(temp_path)

@app.on_event("startup")
async def startup_event():
    global client
    try:
        cookies = extract_cookies()
        if '__Secure-1PSID' not in cookies:
            print("Warning: __Secure-1PSID cookie not found.")
            
        client = GeminiClient(
            secure_1psid=cookies.get('__Secure-1PSID'),
            secure_1psidts=cookies.get('__Secure-1PSIDTS'),
            secure_1psidcc=cookies.get('__Secure-1PSIDCC')
        )
        await client.init(timeout=60)
        print("GeminiClient initialized successfully.")
    except Exception as e:
        print(f"Failed to initialize GeminiClient: {e}")

from fastapi.responses import StreamingResponse
import json

@app.post("/chat")
async def chat(request: ChatRequest):
    global client
    if not client:
        raise HTTPException(status_code=500, detail="GeminiClient not initialized")
    
    async def generate():
        try:
            files = None
            temp_file = None
            if request.file_path and os.path.isfile(request.file_path):
                file_path = request.file_path
                # If the file has no extension, gemini_webapi can't guess MIME type.
                # Copy it to a temp file with the correct extension.
                if not os.path.splitext(file_path)[1]:
                    # Detect image type from header bytes
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
                        ext = ".png"  # fallback
                    import tempfile as _tempfile
                    fd, temp_path = _tempfile.mkstemp(suffix=ext)
                    os.close(fd)
                    shutil.copy2(file_path, temp_path)
                    file_path = temp_path
                    temp_file = temp_path
                files = [file_path]
                print(f"[Gemini Server] Attaching file: {file_path}")
            elif request.file_path:
                print(f"[Gemini Server] Warning: file_path specified but not found: {request.file_path}")
            try:
                async for chunk in client.generate_content_stream(request.prompt, model=request.model or "unspecified", files=files):
                    if hasattr(chunk, 'text_delta') and chunk.text_delta:
                        yield f"data: {json.dumps({'text': chunk.text_delta})}\n\n"
            except Exception as e:
                print(f"[Gemini Server] Chat error: {e}")
                yield f"data: {json.dumps({'error': str(e)})}\n\n"
            finally:
                if temp_file and os.path.exists(temp_file):
                    os.remove(temp_file)
        except Exception as e:
            print(f"[Gemini Server] Setup error: {e}")
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")

@app.get("/models")
async def list_models():
    global client
    if not client:
        return []
    models = client.list_models()
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

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8765)
