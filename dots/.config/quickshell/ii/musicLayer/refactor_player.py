import re

with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/music_backend.py", "r") as f:
    content = f.read()

class Parser:
    def __init__(self, content):
        self.content = content
        self.lines = content.split('\n')
        
    def extract_method(self, method_name):
        start_idx = -1
        end_idx = -1
        
        for i, line in enumerate(self.lines):
            if line.startswith(f"    def {method_name}"):
                start_idx = i
                break
                
        if start_idx == -1:
            return ""
            
        for i in range(start_idx + 1, len(self.lines)):
            line = self.lines[i]
            if line.startswith("    def "):
                end_idx = i
                break
                
        if end_idx == -1:
            end_idx = len(self.lines)
            
        method_lines = self.lines[start_idx:end_idx]
        
        fixed_lines = []
        for line in method_lines:
            if line.startswith("    "):
                fixed_lines.append(line[4:])
            elif line == "":
                fixed_lines.append("")
            else:
                fixed_lines.append(line)
                
        return '\n'.join(fixed_lines)

p = Parser(content)

player_methods = [
    "_sigterm_handler", "_cleanup_on_exit", "_resolve_ytdlp_path", "_cleanup_socket",
    "_push_play_stack", "play", "_prefetch_stream_url", "_play_task",
    "_ipc", "_ipc_get", "stop", "pause", "resume", "seek", "next_track",
    "_auto_continue", "prev_track", "_fetch_queue_task", "fetch_playlist"
]

player_body = ""
for m in player_methods:
    player_body += p.extract_method(m) + "\n"
    
with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/player_methods.py", "w") as f:
    f.write(player_body)

