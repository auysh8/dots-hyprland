import re

with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/music_backend.py", "r") as f:
    content = f.read()

# We need to build the final backend piece by piece.
print("Length of backend: ", len(content))
