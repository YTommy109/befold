# backend/state_store.py
from __future__ import annotations

import json
import traceback
from typing import Any

from backend.logger import logger
from backend.paths import WINDOW_STATE_FILE
from backend.services.window_registry import window_registry


def load_window_states() -> list[dict]:
    """保存済みウィンドウ状態をリストで返す。ファイルがなければ空リスト。"""
    if WINDOW_STATE_FILE.exists():
        try:
            data = json.loads(WINDOW_STATE_FILE.read_text(encoding="utf-8"))
            if isinstance(data, list):
                return data
            if isinstance(data, dict):
                # 旧形式（シングルウィンドウ）に後方互換
                return [
                    {
                        "x": data.get("x", 100),
                        "y": data.get("y", 100),
                        "width": data.get("width", 1024),
                        "height": data.get("height", 768),
                        "file": data.get("last_file"),
                    }
                ]
        except (json.JSONDecodeError, KeyError, OSError):
            pass
    return []


def save_all_states(windows: dict[str, Any], state_cache: dict | None = None) -> None:
    """全ウィンドウの状態を JSON リストとして保存する。

    state_cache: window_id → {x, y, width, height} のキャッシュ。
    win.x 等が None（破棄済みウィンドウ）のときフォールバックとして使う。
    """
    states = []
    cached_all = state_cache or {}
    for wid, win in list(windows.items()):
        watch = window_registry.get_watch(wid)
        path = watch.get_path() if watch else None
        cached = cached_all.get(wid, {})
        states.append(
            {
                "x": win.x if win.x is not None else cached.get("x", 100),
                "y": win.y if win.y is not None else cached.get("y", 100),
                "width": win.width if win.width is not None else cached.get("width", 1024),
                "height": win.height if win.height is not None else cached.get("height", 768),
                "file": str(path) if path else None,
            }
        )
    try:
        WINDOW_STATE_FILE.write_text(json.dumps(states), encoding="utf-8")
    except OSError:
        logger.error("save_all_states: 書き込み失敗\n%s", traceback.format_exc())
