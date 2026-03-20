import re

with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/music_backend.py.backup", "r") as f:
    content = f.read()

# Just extract everything starting with _make_oauth_credentials and ending before the DBus stuff/mpv stuff.
# Actually the easiest way is to use `ast` or regex to pull out the body of the class.

