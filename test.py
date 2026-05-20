import sys
import threading
import time

def background():
    while True:
        time.sleep(1)

t = threading.Thread(target=background)
t.daemon = False
t.start()

for line in sys.stdin:
    pass
print("Done with stdin")
