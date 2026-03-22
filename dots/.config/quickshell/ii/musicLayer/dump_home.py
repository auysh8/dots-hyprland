import json
from ytmusicapi import YTMusic
import traceback

def dump_home():
    try:
        ytm = YTMusic('headers_auth.json')
        home = ytm.get_home(limit=20)
        
        # Print just the titles of the shelves
        print("--- SHELVES ---")
        for shelf in home:
            title = shelf.get("title", "No Title")
            print(f"- {title}")
            
        print("\n--- FIRST SHELF DETAILS ---")
        if home and home[0].get("contents"):
            for i, item in enumerate(home[0]["contents"][:3]):
                print(f"{i+1}. {item.get('title', 'Unknown')} by {item.get('artists', [{'name': 'Unknown'}])[0].get('name') if isinstance(item.get('artists'), list) else item.get('artist', 'Unknown')}")
                
        # Also let's see if there's an active profile or account mentioned
        print("\n--- ACCOUNT MATCH? ---")
        # To verify we are on the right account, we can check liked songs or history
        try:
            history = ytm.get_history()
            if history:
                print(f"History ok, first item: {history[0].get('title')} - {history[0].get('artists', [{}])[0].get('name')}")
            else:
                print("History empty")
        except Exception as e:
            print(f"History error: {e}")
            
    except Exception as e:
        print("Error:")
        traceback.print_exc()

if __name__ == '__main__':
    dump_home()
