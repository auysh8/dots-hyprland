import re

with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/ytm_api.py", "r") as f:
    content = f.read()

cache_methods = """
    def _load_canvas_cache(self):
        try:
            if os.path.exists(self._canvas_cache_path):
                with open(self._canvas_cache_path, "r", encoding="utf-8") as f:
                    self._canvas_cache = json.load(f)
        except Exception:
            self._canvas_cache = {}

    def _save_canvas_cache(self):
        try:
            os.makedirs(os.path.dirname(self._canvas_cache_path), exist_ok=True)
            with open(self._canvas_cache_path, "w", encoding="utf-8") as f:
                json.dump(self._canvas_cache, f)
        except Exception:
            pass
"""

content = content + "\n" + cache_methods

with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/ytm_api.py", "w") as f:
    f.write(content)

