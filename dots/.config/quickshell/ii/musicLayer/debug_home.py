import json
import logging
from ytm_api import YTMClient

logging.basicConfig(level=logging.DEBUG)

def check_home():
    def mock_send(msg):
        if msg.get("type") == "error":
            print("ERROR SENT TO UI:", msg)
        elif msg.get("type") == "home_section":
            print(f"SENT HOME SECTION: {msg.get('section')} with {len(msg.get('items', []))} items")
        else:
            print("SENT OTHER:", msg.get("type"))
            
    api = YTMClient(mock_send, print)
    try:
        print("Fetching home...")
        api._fetch_home_task()
    except Exception as e:
        print(f"Home fetch crashed: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    check_home()
