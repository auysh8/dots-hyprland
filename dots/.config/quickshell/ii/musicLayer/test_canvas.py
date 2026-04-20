import os
import sys
import threading
from cache_manager import CacheManager

def mylog(msg):
    print("LOG: " + str(msg))

cache = CacheManager(cache_dir=os.path.expanduser("~/.cache/quickshell_music"), logger=mylog)
cache.clear(clear_art=False, clear_audio=False, clear_canvas=True)
dummy_path = os.path.abspath("/home/auysh/test.mp4")

# Keep track of active threads
start_threads = threading.active_count()
cache.start_canvas_cache_download("test_vid_123", f"file://{dummy_path}", "Test Title")

import time
while threading.active_count() > start_threads:
    time.sleep(0.1)

print("Done")
