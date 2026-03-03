#!/usr/bin/env python3
"""
Get process list for System Monitor
Outputs JSON array of processes sorted by CPU usage
"""
import subprocess
import json

def parse_memory(mem_str):
    """Parse top memory string (e.g. 100m, 1.2g, 4000) to MB"""
    mem_str = mem_str.lower()
    try:
        if 'g' in mem_str:
            return float(mem_str.replace('g', '')) * 1024
        elif 'm' in mem_str:
            return float(mem_str.replace('m', ''))
        elif 't' in mem_str:
            return float(mem_str.replace('t', '')) * 1024 * 1024
        else:
            # Default is KB
            return float(mem_str) / 1024
    except ValueError:
        return 0.0

def get_processes():
    try:
        # Use top in batch mode to get real-time CPU usage
        # -b: batch mode
        # -n 1: single iteration
        # -c: show full command line
        # -w 512: wide output to prevent command truncation
        result = subprocess.run(
            ['top', '-b', '-n', '1', '-c', '-w', '512'],
            capture_output=True,
            text=True
        )
        
        processes = []
        lines = result.stdout.strip().split('\n')
        
        # Find the header line starting with PID
        header_idx = -1
        for i, line in enumerate(lines):
            if line.strip().startswith('PID'):
                header_idx = i
                break
        
        if header_idx == -1:
            return []
            
        # Parse process lines (skip header)
        for line in lines[header_idx+1:]:
            parts = line.split()
            if len(parts) >= 12:
                try:
                    # Parse command and get icon name
                    full_command = " ".join(parts[11:])
                    cmd_path = full_command.split()[0]
                    
                    # Clean up command path
                    if cmd_path.startswith('['):
                        # Kernel thread
                        icon_name = "system-run"
                        display_name = full_command
                    else:
                        base_name = cmd_path.split('/')[-1]
                        # Remove special chars
                        base_name = base_name.strip(':').strip()
                        
                        # Common mappings for Icon
                        if "python" in base_name: icon_name = "application-x-python"
                        elif "zen" in base_name: icon_name = "zen-browser"
                        elif "firefox" in base_name: icon_name = "firefox"
                        elif "chrome" in base_name: icon_name = "google-chrome"
                        elif "kitty" in base_name: icon_name = "kitty"
                        elif "alacritty" in base_name: icon_name = "Alacritty"
                        elif "qs" in base_name or "quickshell" in base_name: icon_name = "quickshell"
                        elif "hyprland" in base_name.lower(): icon_name = "hyprland"
                        else:
                            icon_name = base_name
                            
                        # Better Display Name
                        if "python" in base_name and len(parts) > 12:
                            # Show script name for python: "python3 script.py" -> "script.py"
                            script = parts[12].split('/')[-1]
                            display_name = script
                        else:
                            display_name = base_name
                            # Cap length
                            if len(display_name) > 30: display_name = display_name[:30] + "..."

                    processes.append({
                        "user": parts[1],      # USER
                        "pid": int(parts[0]),  # PID
                        "cpu": float(parts[8]), # %CPU
                        "mem": float(parts[9]), # %MEM
                        "res_mb": parse_memory(parts[5]), # RES (Physical Memory)
                        "command": display_name, # CLEAN NAME
                        "full_command": full_command, # Full command for reference
                        "processIcon": icon_name      # Derived icon name
                    })
                except (ValueError, IndexError):
                    continue
        
        # Sort by CPU descending
        processes.sort(key=lambda x: x['cpu'], reverse=True)
        return processes[:500]
    except Exception as e:
        return []

if __name__ == "__main__":
    print(json.dumps(get_processes()))
