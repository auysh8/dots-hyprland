# Commands to run in interactive sessions can go here
if status is-interactive
    # No greeting
    set fish_greeting

    # Use starship
    function starship_transient_prompt_func
        starship module character
    end
    if test "$TERM" != "linux"
        starship init fish | source
        # enable_transience # Disabled: known to cause bugs where typed text doesn't display in fish
    end
    
    # Colors
    if test "$TERM" != "xterm-kitty"; and test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
        cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    end

    # Aliases
    # kitty doesn't clear properly so we need to do this weird printing
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias pamcan pacman
    alias q 'qs -c ii'
    if test "$TERM" != "linux"
        alias ls 'eza --icons'
    end
    if test "$TERM" = "xterm-kitty"
        alias ssh 'kitten ssh'
    end
end

# OpenClaw Completion
if test -f "/home/auysh/.openclaw/completions/openclaw.fish"
    source "/home/auysh/.openclaw/completions/openclaw.fish"
end

fish_add_path /home/auysh/.spicetify

# Qwen API & Goose AI Agent exports
set -gx OPENAI_API_BASE "https://qwen.aikit.club/v1"
set -gx OPENAI_BASE_URL "https://qwen.aikit.club/v1"
set -gx OPENAI_API_KEY "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjYzNGRlODlhLTM2NGYtNDM5MC04MjM3LWNkNTFlOWM3Yzk3MiIsImxhc3RfcGFzc3dvcmRfY2hhbmdlIjoxNzUwNjYwODczLCJleHAiOjE3ODkxODU0MDZ9.WHxTZDkuetw0czcWhvD1Ite8w9amFZykXZuUaCRU6Aw"
set -gx GOOSE_PROVIDER "openai"
set -gx GOOSE_MODEL "qwen3.8-max"



