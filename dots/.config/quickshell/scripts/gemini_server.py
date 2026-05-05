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
        await client.init()
        print("GeminiClient initialized successfully.")
    except Exception as e:
        print(f"Failed to initialize GeminiClient: {e}")

@app.post("/chat")
async def chat(request: ChatRequest):
    global client
    if not client:
        raise HTTPException(status_code=500, detail="GeminiClient not initialized")
    
    try:
        response = await client.generate_content(request.prompt)
        return {"response": response.text}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000)
