from pathlib import Path

APP_DATA_DIR = Path.home() / "Library" / "Application Support" / "mmdview"
APP_DATA_DIR.mkdir(parents=True, exist_ok=True)

WINDOW_STATE_FILE = APP_DATA_DIR / "window_state.json"
