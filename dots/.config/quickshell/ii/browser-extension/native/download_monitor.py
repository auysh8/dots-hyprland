#!/usr/bin/env python3
import sys
import json
import struct
import os
import signal

# Path for the runtime status file
RUNTIME_FILE = "/tmp/quickshell_downloads.json"

def get_message():
    raw_length = sys.stdin.buffer.read(4)
    if not raw_length:
        return None
    message_length = struct.unpack('@I', raw_length)[0]
    message = sys.stdin.buffer.read(message_length).decode('utf-8')
    return json.loads(message)

def send_message(message_content):
    encoded_content = json.dumps(message_content).encode('utf-8')
    encoded_length = struct.pack('@I', len(encoded_content))
    sys.stdout.buffer.write(encoded_length)
    sys.stdout.buffer.write(encoded_content)
    sys.stdout.buffer.flush()

def write_status(data):
    try:
        with open(RUNTIME_FILE + ".tmp", "w") as f:
            json.dump(data, f)
        os.rename(RUNTIME_FILE + ".tmp", RUNTIME_FILE)
    except Exception as e:
        pass # Fail silently to keep the pipe open

def main():
    # Handle signals to ensure clean exit
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    while True:
        try:
            message = get_message()
            if message:
                # We received download info from the browser
                write_status(message)
                # Echo back to confirm receipt (optional, but good for debugging)
                send_message({"status": "received"})
            else:
                break
        except Exception as e:
            break

if __name__ == '__main__':
    main()
