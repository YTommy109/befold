# コードレビュー改善 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** コードレビューで指摘された6項目（CDN修正・二重管理解消・クラス化・app.py分割・フォールバック改善・JS外部化）を順次改善する。

**Architecture:** 各タスクは独立したコミットとして進める。サービス層（Task 2,3）→ エントリポイント層（Task 4）→ ルーター/テンプレート層（Task 1,5,6）の順で依存関係の低い方から高い方へ。

**Tech Stack:** Python 3.12, FastAPI, Jinja2, htmx, pywebview, pytest

<!-- derived-from ../specs/2026-06-06-refactor-review-design.md -->

---

## ファイル一覧

| 操作 | パス | 説明 |
|------|------|------|
| Modify | `backend/templates/update_dialog.html` | CDN→ローカル htmx |
| Modify | `backend/services/window_registry.py` | `_Entry.path` 削除 |
| Modify | `tests/unit/test_window_registry.py` | snapshot テスト更新 |
| Modify | `backend/services/update_service.py` | クラス化 |
| Modify | `tests/unit/test_update_service.py` | クラス対応に書き直し |
| Modify | `backend/routers/update.py` | import パス更新 |
| Modify | `backend/update_window.py` | import パス更新 |
| Create | `backend/server.py` | サーバー起動ユーティリティ |
| Create | `backend/state_store.py` | ウィンドウ状態永続化 |
| Create | `backend/window_manager.py` | ウィンドウ生成・管理 |
| Modify | `backend/app.py` | main() + Apple Events パッチのみ |
| Modify | `pyproject.toml` | coverage omit 追加 |
| Modify | `backend/routers/update.py` | do_install フォールバック修正 |
| Create | `static/js/viewer.js` | viewer.html から抽出した JS |
| Modify | `backend/templates/viewer.html` | インライン JS を外部ファイルへ |

---

## Task 1: `update_dialog.html` CDN参照をローカルに修正

**Files:**
- Modify: `backend/templates/update_dialog.html:7`

- [ ] **Step 1: CDN参照をローカルに変更する**

`backend/templates/update_dialog.html` の7行目を変更する:

```html
<!-- 変更前 -->
<script src="https://unpkg.com/htmx.org@2.0.4" integrity="sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+" crossorigin="anonymous"></script>

<!-- 変更後 -->
<script src="/static/js/htmx.min.js"></script>
```

- [ ] **Step 2: インポートエラーがないか確認する**

```bash
python -c "from backend.main import app; print('OK')"
```

期待出力: `OK`

- [ ] **Step 3: コミットする**

```bash
git add backend/templates/update_dialog.html
git commit -m "fix: update_dialog の htmx を CDN からローカルに切り替える"
```

---

## Task 2: `_Entry.path` の二重管理を解消する

**Files:**
- Modify: `backend/services/window_registry.py`
- Modify: `tests/unit/test_window_registry.py`

- [ ] **Step 1: `_Entry.path` を削除し `watch.get_path()` 経由に変更する**

`backend/services/window_registry.py` を以下に書き換える:

```python
# backend/services/window_registry.py
import asyncio
from dataclasses import dataclass
from pathlib import Path

from backend.services.event_bus import EventBus
from backend.services.watch_service import WatchService


@dataclass
class _Entry:
    watch: WatchService
    bus: EventBus


class WindowRegistry:
    def __init__(self) -> None:
        self._entries: dict[str, _Entry] = {}
        self._loop: asyncio.AbstractEventLoop | None = None

    def set_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        self._loop = loop

    def create(self, window_id: str, file_path: str | None = None) -> None:
        if window_id in self._entries:
            self.remove(window_id)
        bus = EventBus()
        if self._loop is not None:
            bus.set_loop(self._loop)
        watch = WatchService(event_bus=bus)
        if file_path:
            watch.set_file(file_path)
        self._entries[window_id] = _Entry(watch=watch, bus=bus)

    def get_watch(self, window_id: str) -> WatchService | None:
        entry = self._entries.get(window_id)
        return entry.watch if entry else None

    def get_bus(self, window_id: str) -> EventBus | None:
        entry = self._entries.get(window_id)
        return entry.bus if entry else None

    def remove(self, window_id: str) -> None:
        entry = self._entries.pop(window_id, None)
        if entry:
            entry.watch.stop()

    def find_by_path(self, path: str) -> str | None:
        p = Path(path)
        for wid, entry in self._entries.items():
            if entry.watch.get_path() == p:
                return wid
        return None

    def snapshot(self) -> list[tuple[str, Path | None]]:
        return [(wid, entry.watch.get_path()) for wid, entry in self._entries.items()]


window_registry = WindowRegistry()
```

- [ ] **Step 2: テストを実行して既存テストが通ることを確認する**

```bash
pytest tests/unit/test_window_registry.py -v
```

期待出力: 全テスト PASSED

- [ ] **Step 3: コミットする**

```bash
git add backend/services/window_registry.py
git commit -m "refactor: _Entry.path を削除し watch.get_path() 経由に統一する"
```

---

## Task 3: `update_service.py` をクラス化する

**Files:**
- Modify: `backend/services/update_service.py`
- Modify: `tests/unit/test_update_service.py`
- Modify: `backend/routers/update.py`
- Modify: `backend/update_window.py`

- [ ] **Step 1: 新しいテストを書く**

`tests/unit/test_update_service.py` を以下に書き換える:

```python
# tests/unit/test_update_service.py
"""UpdateService クラスの単体テスト。"""

from __future__ import annotations

import os
from unittest.mock import MagicMock, patch

import pytest

from backend.services.update_service import UpdateService, _CURRENT_VERSION


@pytest.fixture
def svc() -> UpdateService:
    return UpdateService()


def _make_github_response(tag: str, assets: list[dict] | None = None) -> MagicMock:
    mock = MagicMock()
    mock.json.return_value = {"tag_name": tag, "assets": assets or []}
    mock.raise_for_status = MagicMock()
    return mock


def test_check_update_新バージョンあり(svc: UpdateService) -> None:
    assets = [
        {"name": "mmdview-v999.9.9.dmg", "browser_download_url": "https://example.com/test.dmg"}
    ]
    with patch("backend.services.update_service.httpx.get", return_value=_make_github_response("v999.9.9", assets)):
        result = svc.check_update()
    assert result["available"] is True
    assert result["version"] == "999.9.9"
    assert result["download_url"] == "https://example.com/test.dmg"


def test_check_update_最新バージョン(svc: UpdateService) -> None:
    with patch("backend.services.update_service.httpx.get", return_value=_make_github_response(f"v{_CURRENT_VERSION}")):
        result = svc.check_update()
    assert result["available"] is False


def test_check_update_キャッシュが効く(svc: UpdateService) -> None:
    with patch("backend.services.update_service.httpx.get", return_value=_make_github_response("v0.2.0")) as mock_get:
        svc.check_update()
        svc.check_update()
    assert mock_get.call_count == 1


def test_check_update_MMDVIEW_MOCK_DMG環境変数でモック結果を返す(svc: UpdateService) -> None:
    with patch.dict(os.environ, {"MMDVIEW_MOCK_DMG": "/tmp/mmdview-test.dmg"}):
        result = svc.check_update()
    assert result["available"] is True
    assert result["version"] == "999.0.0"
    assert result["download_url"] is None


def test_get_download_state_MMDVIEW_MOCK_DMG環境変数でdone状態を返す(svc: UpdateService) -> None:
    with patch.dict(os.environ, {"MMDVIEW_MOCK_DMG": "/tmp/mmdview-test.dmg"}):
        result = svc.get_download_state()
    assert result["status"] == "done"
    assert result["percent"] == 100
    assert result["dmg_path"] == "/tmp/mmdview-test.dmg"


def test_download_update_進捗更新(svc: UpdateService, tmp_path) -> None:
    chunk_data = [b"a" * 50, b"b" * 50]
    dmg_dest = tmp_path / "test.dmg"

    class FakeResponse:
        headers = {"content-length": "100"}

        def raise_for_status(self) -> None:
            pass

        def iter_bytes(self, chunk_size: int | None = None):
            return iter(chunk_data)

        def __enter__(self):
            return self

        def __exit__(self, *args) -> bool:
            return False

    with patch("backend.services.update_service.httpx.stream", return_value=FakeResponse()):
        svc._do_download("https://example.com/test.dmg", dest=dmg_dest)

    state = svc.get_download_state()
    assert state["status"] == "done"
    assert state["percent"] == 100
    assert state["dmg_path"] == str(dmg_dest)


def test_invalidate_cache_はキャッシュをクリアする(svc: UpdateService) -> None:
    import time

    svc._cache["checked_at"] = time.monotonic()
    svc._cache["result"] = {"available": False, "version": "0.1.0", "download_url": None}
    svc.invalidate_cache()
    assert svc._cache["checked_at"] is None
    assert svc._cache["result"] is None
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
pytest tests/unit/test_update_service.py -v 2>&1 | head -30
```

期待出力: `ImportError` または `AttributeError`（`UpdateService` クラスがまだ存在しないため）

- [ ] **Step 3: `update_service.py` をクラス化する**

`backend/services/update_service.py` を以下に書き換える:

```python
# backend/services/update_service.py
"""アプリ内自動アップデート処理。"""

from __future__ import annotations

import logging
import os
import threading
import time
from pathlib import Path

import httpx

from backend.version import __version__ as _CURRENT_VERSION

GITHUB_API_URL = "https://api.github.com/repos/YTommy109/mmdview/releases/latest"
_CACHE_TTL = 3600
_logger = logging.getLogger(__name__)


class UpdateService:
    def __init__(self) -> None:
        self._cache: dict = {"checked_at": None, "result": None}
        self._download_state: dict = {"percent": 0, "status": "idle", "dmg_path": None}
        self._state_lock = threading.Lock()

    def _is_newer(self, remote: str, current: str) -> bool:
        def to_tuple(v: str) -> tuple[int, ...]:
            return tuple(int(x) for x in v.split("."))
        return to_tuple(remote) > to_tuple(current)

    def _find_dmg_url(self, assets: list[dict]) -> str | None:
        for asset in assets:
            if asset.get("name", "").endswith(".dmg"):
                return asset.get("browser_download_url")
        return None

    def check_update(self) -> dict:
        """GitHub Releases API で最新バージョンを確認する（1時間TTLキャッシュ）。

        MMDVIEW_MOCK_DMG が設定されている場合は GitHub を呼ばずモック結果を返す。
        """
        if os.environ.get("MMDVIEW_MOCK_DMG"):
            return {"available": True, "version": "999.0.0", "download_url": None}
        now = time.monotonic()
        if self._cache["checked_at"] and now - self._cache["checked_at"] < _CACHE_TTL:
            return self._cache["result"]
        try:
            resp = httpx.get(GITHUB_API_URL, timeout=5, follow_redirects=True)
            resp.raise_for_status()
            data = resp.json()
            tag = data["tag_name"].lstrip("v")
            result: dict = {
                "available": self._is_newer(tag, _CURRENT_VERSION),
                "version": tag,
                "download_url": self._find_dmg_url(data.get("assets", [])),
            }
        except Exception:
            result = {"available": False, "version": _CURRENT_VERSION, "download_url": None}
        self._cache["checked_at"] = now
        self._cache["result"] = result
        _logger.info("更新確認: available=%s version=%s", result["available"], result["version"])
        return result

    def get_download_state(self) -> dict:
        """ダウンロード状態のコピーを返す。

        MMDVIEW_MOCK_DMG が設定されている場合はそのパスで完了状態を返す。
        """
        if mock_dmg := os.environ.get("MMDVIEW_MOCK_DMG"):
            return {"percent": 100, "status": "done", "dmg_path": mock_dmg}
        with self._state_lock:
            return dict(self._download_state)

    def _do_download(self, url: str, dest: Path | None = None) -> None:
        """実際のダウンロード処理（バックグラウンドスレッドで実行）。"""
        with self._state_lock:
            self._download_state.update({"percent": 0, "status": "downloading", "dmg_path": None})
        dmg_path = dest or Path.home() / "Downloads" / "mmdview-update.dmg"
        try:
            with httpx.stream("GET", url, follow_redirects=True, timeout=300) as resp:
                resp.raise_for_status()
                total = int(resp.headers.get("content-length", 0))
                downloaded = 0
                with dmg_path.open("wb") as f:
                    for chunk in resp.iter_bytes(chunk_size=65536):
                        f.write(chunk)
                        downloaded += len(chunk)
                        if total > 0:
                            with self._state_lock:
                                self._download_state["percent"] = int(downloaded / total * 100)
            with self._state_lock:
                self._download_state["status"] = "done"
                self._download_state["dmg_path"] = str(dmg_path)
        except Exception:
            _logger.error("ダウンロード失敗: url=%s", url, exc_info=True)
            with self._state_lock:
                self._download_state["status"] = "error"

    def invalidate_cache(self) -> None:
        """更新確認キャッシュを無効化する。"""
        self._cache["checked_at"] = None
        self._cache["result"] = None

    def download_update(self, url: str) -> None:
        """ダウンロードをバックグラウンドスレッドで開始する。"""
        with self._state_lock:
            if self._download_state["status"] == "downloading":
                return
        threading.Thread(target=self._do_download, args=(url,), daemon=True).start()


update_service = UpdateService()
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
pytest tests/unit/test_update_service.py -v
```

期待出力: 全テスト PASSED

- [ ] **Step 5: `routers/update.py` の import を更新する**

`backend/routers/update.py` の import 行を変更する:

```python
# 変更前
from backend.services import update_service

# 変更後
from backend.services.update_service import update_service
```

- [ ] **Step 6: `update_window.py` の import を更新する**

`backend/update_window.py` の import 行を変更する:

```python
# 変更前
from backend.services import update_service

# 変更後
from backend.services.update_service import update_service
```

- [ ] **Step 7: 全テストを実行する**

```bash
pytest -v 2>&1 | tail -20
```

期待出力: 全テスト PASSED、カバレッジ 80% 以上

- [ ] **Step 8: コミットする**

```bash
git add backend/services/update_service.py \
        tests/unit/test_update_service.py \
        backend/routers/update.py \
        backend/update_window.py
git commit -m "refactor: update_service をクラス化し状態をインスタンス変数に移動する"
```

---

## Task 4: `app.py` を責務ごとに分割する

**Files:**
- Create: `backend/server.py`
- Create: `backend/state_store.py`
- Create: `backend/window_manager.py`
- Modify: `backend/app.py`
- Modify: `pyproject.toml`（coverage omit 追加）

### Step 4-1: `backend/server.py` を作成する

- [ ] **Step 1: `server.py` を作成する**

```python
# backend/server.py
import socket
import threading
import time

import uvicorn


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def start_server(app, port: int) -> None:
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="error")


def wait_for_server(port: int, timeout: float = 5.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                return
        except OSError:
            time.sleep(0.05)
    raise RuntimeError(f"Server did not start on port {port} within {timeout}s")


def start_server_thread(app, port: int) -> threading.Thread:
    t = threading.Thread(target=start_server, args=(app, port), daemon=True)
    t.start()
    return t
```

- [ ] **Step 2: `find_free_port` と `wait_for_server` のテストを書く**

`tests/unit/test_server.py` を新規作成する:

```python
# tests/unit/test_server.py
import socket
import threading
import time

from backend.server import find_free_port, wait_for_server


def test_find_free_port_returns_available_port():
    port = find_free_port()
    assert isinstance(port, int)
    assert 1024 < port < 65536
    # ポートが実際に使えることを確認する
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", port))


def test_wait_for_server_succeeds_when_server_is_up():
    port = find_free_port()

    def _serve():
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("127.0.0.1", port))
            s.listen(1)
            s.accept()

    t = threading.Thread(target=_serve, daemon=True)
    t.start()
    time.sleep(0.05)
    wait_for_server(port, timeout=2.0)


def test_wait_for_server_raises_when_timeout():
    port = find_free_port()
    import pytest
    with pytest.raises(RuntimeError, match="did not start"):
        wait_for_server(port, timeout=0.1)
```

- [ ] **Step 3: テストを実行する**

```bash
pytest tests/unit/test_server.py -v
```

期待出力: 3テスト PASSED

### Step 4-2: `backend/state_store.py` を作成する

- [ ] **Step 4: `state_store.py` を作成する**

```python
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


def save_all_states(windows: dict[str, Any]) -> None:
    """全ウィンドウの状態を JSON リストとして保存する。"""
    states = []
    for wid, win in list(windows.items()):
        watch = window_registry.get_watch(wid)
        path = watch.get_path() if watch else None
        states.append(
            {
                "x": win.x,
                "y": win.y,
                "width": win.width,
                "height": win.height,
                "file": str(path) if path else None,
            }
        )
    try:
        WINDOW_STATE_FILE.write_text(json.dumps(states), encoding="utf-8")
    except OSError:
        logger.error("save_all_states: 書き込み失敗\n%s", traceback.format_exc())
```

- [ ] **Step 5: `load_window_states` のテストを書く**

`tests/unit/test_state_store.py` を新規作成する:

```python
# tests/unit/test_state_store.py
import json
from pathlib import Path
from unittest.mock import patch

from backend.state_store import load_window_states


def _patch_state_file(tmp_path, content):
    state_file = tmp_path / "window_state.json"
    if content is not None:
        state_file.write_text(json.dumps(content), encoding="utf-8")
    return state_file


def test_load_window_states_ファイルなしで空リストを返す(tmp_path):
    state_file = tmp_path / "window_state.json"
    with patch("backend.state_store.WINDOW_STATE_FILE", state_file):
        result = load_window_states()
    assert result == []


def test_load_window_states_リスト形式を読み込む(tmp_path):
    data = [{"x": 10, "y": 20, "width": 800, "height": 600, "file": "/tmp/a.mmd"}]
    state_file = _patch_state_file(tmp_path, data)
    with patch("backend.state_store.WINDOW_STATE_FILE", state_file):
        result = load_window_states()
    assert result == data


def test_load_window_states_旧形式dictを変換する(tmp_path):
    data = {"x": 50, "y": 60, "width": 1024, "height": 768, "last_file": "/tmp/b.mmd"}
    state_file = _patch_state_file(tmp_path, data)
    with patch("backend.state_store.WINDOW_STATE_FILE", state_file):
        result = load_window_states()
    assert len(result) == 1
    assert result[0]["x"] == 50
    assert result[0]["file"] == "/tmp/b.mmd"


def test_load_window_states_壊れたJSONで空リストを返す(tmp_path):
    state_file = tmp_path / "window_state.json"
    state_file.write_text("INVALID JSON", encoding="utf-8")
    with patch("backend.state_store.WINDOW_STATE_FILE", state_file):
        result = load_window_states()
    assert result == []
```

- [ ] **Step 6: テストを実行する**

```bash
pytest tests/unit/test_state_store.py -v
```

期待出力: 4テスト PASSED

### Step 4-3: `backend/window_manager.py` を作成する

- [ ] **Step 7: `window_manager.py` を作成する**

```python
# backend/window_manager.py
import sys
import threading
from pathlib import Path
from uuid import uuid4

import webview
from webview import FileDialog
from webview.menu import Menu, MenuAction, MenuSeparator

from backend.logger import logger
from backend.services.recent_files_service import recent_files_service
from backend.services.window_registry import window_registry
from backend import state_store

_windows: dict[str, webview.Window] = {}


def get_windows() -> dict[str, webview.Window]:
    return _windows


def focus_window(window: webview.Window) -> None:
    """ウィンドウをフロントに持ってくるベストエフォート実装。"""
    try:
        window.evaluate_js("window.focus()")
        if sys.platform == "darwin":
            from AppKit import NSApp  # type: ignore[import]
            NSApp.activateIgnoringOtherApps_(True)
    except Exception:
        pass


def create_window(
    port: int,
    file_path: str | None = None,
    x: int = 100,
    y: int = 100,
    width: int = 1024,
    height: int = 768,
) -> tuple[str, webview.Window]:
    """新しいウィンドウを作成し、registry と _windows に登録して返す。"""
    window_id = str(uuid4())
    logger.info("create_window: file_path=%s window_id=%s", file_path, window_id)
    window_registry.create(window_id, file_path)

    title = Path(file_path).name if file_path else "mmdview"
    try:
        window = webview.create_window(
            title,
            f"http://127.0.0.1:{port}/?window_id={window_id}",
            x=x,
            y=y,
            width=width,
            height=height,
        )
    except Exception:
        window_registry.remove(window_id)
        raise

    if window is None:
        window_registry.remove(window_id)
        raise RuntimeError(f"webview.create_window returned None for window_id={window_id}")

    _windows[window_id] = window

    _save_timer: threading.Timer | None = None

    def _schedule_save() -> None:
        nonlocal _save_timer
        if _save_timer:
            _save_timer.cancel()
        _save_timer = threading.Timer(0.5, lambda: state_store.save_all_states(_windows))
        _save_timer.start()

    window.events.moved += lambda x, y: _schedule_save()
    window.events.resized += lambda width, height: _schedule_save()

    def _on_closed() -> None:
        _windows.pop(window_id, None)
        window_registry.remove(window_id)
        state_store.save_all_states(_windows)

    window.events.closed += _on_closed
    return window_id, window


def open_file(path: str, port: int) -> None:
    """ファイルを開く。既に開いていれば既存ウィンドウをフォーカスし、なければ新規作成。"""
    existing_id = window_registry.find_by_path(path)
    if existing_id:
        win = _windows.get(existing_id)
        if win is not None:
            logger.info("open_file: already open, focusing: %s", path)
            focus_window(win)
            return
        logger.warning(
            "open_file: registry has window_id=%s but not in _windows, opening new: %s",
            existing_id,
            path,
        )
    logger.info("open_file: opening new window: %s", path)
    create_window(port, file_path=path)


def open_file_from_menu(port: int) -> None:
    if not webview.windows:
        return
    result = webview.windows[0].create_file_dialog(
        FileDialog.OPEN,
        allow_multiple=False,
        file_types=("Mermaid files (*.mmd;*.mermaid)", "All files (*.*)"),
    )
    if result:
        recent_files_service.add(result[0])
        open_file(result[0], port)


def build_open_recent_menu(port: int) -> Menu:
    recent = recent_files_service.get()

    def _open_recent(path: str) -> None:
        recent_files_service.add(path)
        open_file(path, port)

    if recent:
        items: list = [MenuAction(p, lambda p=p: _open_recent(p)) for p in recent]
        items += [MenuSeparator(), MenuAction("Clear Menu", recent_files_service.clear)]
    else:
        items = [MenuAction("No Recent Files", lambda: None)]

    return Menu("Open Recent...", items)
```

### Step 4-4: `backend/app.py` を簡略化する

- [ ] **Step 8: `app.py` を書き換える**

```python
# backend/app.py
import sys
import threading
import traceback

import webview
from webview.menu import Menu, MenuAction

from backend.logger import logger
from backend.main import app as fastapi_app
from backend.server import find_free_port, start_server_thread, wait_for_server
from backend.services.recent_files_service import recent_files_service
from backend.services.window_registry import window_registry
from backend import state_store, window_manager


def _patch_app_delegate_for_open_file(callback) -> None:
    """NSApp.finishLaunching() が odoc ハンドラを上書きするため、
    applicationDidFinishLaunching_ で再登録するようにパッチを当てる。"""
    if sys.platform != "darwin":
        return
    try:
        from webview.platforms import cocoa as _cocoa  # type: ignore[import]
        from backend.apple_events import register_open_file_handler

        def _did_finish_launching(self: object, notification: object) -> None:
            logger.info("_did_finish_launching fired: re-registering odoc handler")
            register_open_file_handler(callback)

        _cocoa.BrowserView.AppDelegate.applicationDidFinishLaunching_ = _did_finish_launching
        logger.info("applicationDidFinishLaunching_ patch applied successfully")
    except Exception:
        logger.warning(
            "applicationDidFinishLaunching_ パッチに失敗しました\n%s", traceback.format_exc()
        )


def main() -> None:
    from backend.version import __version__

    logger.info("mmdview %s starting: argv=%s", __version__, sys.argv)

    port = find_free_port()
    start_server_thread(fastapi_app, port)
    wait_for_server(port)

    def _on_open_file(path: str) -> None:
        logger.info("_on_open_file called: path=%s", path)
        recent_files_service.add(path)

        def _run() -> None:
            try:
                window_manager.open_file(path, port)
            except Exception:
                logger.error("open_file failed: path=%s\n%s", path, traceback.format_exc())

        threading.Thread(target=_run, daemon=True).start()

    if len(sys.argv) > 1:
        cli_file = sys.argv[1]
        recent_files_service.add(cli_file)
        window_manager.create_window(port, file_path=cli_file)
    else:
        states = state_store.load_window_states()
        if states:
            for s in states:
                window_manager.create_window(
                    port,
                    file_path=s.get("file"),
                    x=s.get("x", 100),
                    y=s.get("y", 100),
                    width=s.get("width", 1024),
                    height=s.get("height", 768),
                )
        else:
            window_manager.create_window(port)

    menu = [
        Menu(
            "File",
            [
                MenuAction("Open...", lambda: window_manager.open_file_from_menu(port)),
                window_manager.build_open_recent_menu(port),
            ],
        )
    ]

    from backend.apple_events import register_open_file_handler
    from backend.update_window import setup_app_menu

    register_open_file_handler(_on_open_file)
    _patch_app_delegate_for_open_file(_on_open_file)

    def _on_webview_ready() -> None:
        setup_app_menu(port)

    webview.start(menu=menu, func=_on_webview_ready)

    for wid, _ in window_registry.snapshot():
        window_registry.remove(wid)


if __name__ == "__main__":
    main()
```

- [ ] **Step 9: `pyproject.toml` の coverage omit に新ファイルを追加する**

`pyproject.toml` の `[tool.coverage.run]` セクションを変更する:

```toml
[tool.coverage.run]
source = ["backend"]
omit = [
    "tests/*",
    "backend/app.py",
    "backend/window_manager.py",
    "backend/update_window.py",
    "backend/apple_events.py",
]
```

- [ ] **Step 10: インポートエラーがないか確認する**

```bash
python -c "from backend import server, state_store, window_manager; print('OK')"
```

期待出力: `OK`

- [ ] **Step 11: 全テストを実行する**

```bash
pytest -v 2>&1 | tail -20
```

期待出力: 全テスト PASSED、カバレッジ 80% 以上

- [ ] **Step 12: コミットする**

```bash
git add backend/server.py \
        backend/state_store.py \
        backend/window_manager.py \
        backend/app.py \
        pyproject.toml \
        tests/unit/test_server.py \
        tests/unit/test_state_store.py
git commit -m "refactor: app.py を server / state_store / window_manager に分割する"
```

---

## Task 5: `do_install` フォールバックを改善する

**Files:**
- Modify: `backend/routers/update.py:71-79`

- [ ] **Step 1: `do_install` の空レスポンスを修正する**

`backend/routers/update.py` の `do_install` 関数を変更する:

```python
@router.post("/install", response_class=HTMLResponse)
def do_install(request: Request) -> HTMLResponse:
    result = install_update()
    if result == "not_frozen":
        return templates.TemplateResponse(request, "partials/update_idle.html", {})
    state = {"percent": 100, "status": f"install_error:{result}"}
    return templates.TemplateResponse(
        request,
        "partials/update_progress.html",
        {"percent": 100, "status": state["status"]},
    )
```

- [ ] **Step 2: 統合テストを更新する（存在する場合）**

```bash
pytest tests/integration/ -v -k "update" 2>&1 | tail -20
```

期待出力: 全テスト PASSED（またはテストなしの場合 `no tests ran`）

- [ ] **Step 3: コミットする**

```bash
git add backend/routers/update.py
git commit -m "fix: do_install の not_frozen 時に空レスポンスではなく update_idle を返す"
```

---

## Task 6: `viewer.html` のインライン JS を外部ファイルへ

**Files:**
- Create: `static/js/viewer.js`
- Modify: `backend/templates/viewer.html`

- [ ] **Step 1: `static/js/viewer.js` を作成する**

```javascript
// static/js/viewer.js
mermaid.initialize({
  startOnLoad: true,
  theme: 'default',
  sequence: { useMaxWidth: false },
  er: { useMaxWidth: false },
  flowchart: { useMaxWidth: false },
  gantt: { useMaxWidth: false },
  journey: { useMaxWidth: false },
  pie: { useMaxWidth: false },
  state: { useMaxWidth: false },
  class: { useMaxWidth: false },
});

const ZOOM_MIN = 0.5;
const ZOOM_MAX = 2.0;
const ZOOM_STEP = 0.25;

let zoom = parseFloat(localStorage.getItem('mmdview.viewer.zoom') || '1');
if (isNaN(zoom)) zoom = 1;

const wrap = document.getElementById('diagram-wrap');
const label = document.getElementById('zoom-label');
const btnIn = document.getElementById('zoom-in');
const btnOut = document.getElementById('zoom-out');

function applyZoom() {
  zoom = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, zoom));
  wrap.style.zoom = zoom;
  label.textContent = Math.round(zoom * 100) + '%';
  btnIn.disabled = zoom >= ZOOM_MAX;
  btnOut.disabled = zoom <= ZOOM_MIN;
  localStorage.setItem('mmdview.viewer.zoom', zoom);
}

btnIn.addEventListener('click', () => {
  zoom = Math.round((zoom + ZOOM_STEP) * 100) / 100;
  applyZoom();
});

btnOut.addEventListener('click', () => {
  zoom = Math.round((zoom - ZOOM_STEP) * 100) / 100;
  applyZoom();
});

label.addEventListener('click', () => {
  zoom = 1;
  applyZoom();
});

document.addEventListener('wheel', (e) => {
  if (!e.ctrlKey) return;
  e.preventDefault();
  zoom = Math.round((zoom - e.deltaY * 0.01) * 1000) / 1000;
  applyZoom();
}, { passive: false });

document.addEventListener('keydown', (e) => {
  if (!e.metaKey) return;
  if (e.key === '=' || e.key === '+') {
    e.preventDefault();
    zoom = Math.round((zoom + ZOOM_STEP) * 100) / 100;
    applyZoom();
  } else if (e.key === '-') {
    e.preventDefault();
    zoom = Math.round((zoom - ZOOM_STEP) * 100) / 100;
    applyZoom();
  }
});

const wid = new URLSearchParams(window.location.search).get('window_id') || '';
const evtSource = new EventSource('/events?window_id=' + encodeURIComponent(wid));
evtSource.onmessage = (e) => {
  if (e.data === 'reload') window.location.reload();
};

applyZoom();
```

- [ ] **Step 2: `viewer.html` の `<script>` ブロックを外部ファイル参照に置き換える**

`backend/templates/viewer.html` を以下に変更する:

```html
{% extends "base.html" %}
{% block content %}
<div class="viewer">
  <div id="diagram-wrap">
    <pre class="mermaid">{{ content }}</pre>
  </div>
</div>

<div class="zoom-controls">
  <button id="zoom-out" title="縮小 (Cmd −)">−</button>
  <span id="zoom-label" title="クリックでリセット">100%</span>
  <button id="zoom-in" title="拡大 (Cmd +)">+</button>
</div>

<script src="/static/js/mermaid.min.js"></script>
<script src="/static/js/viewer.js"></script>
{% endblock %}
```

- [ ] **Step 3: インポートエラーがないか確認する**

```bash
python -c "from backend.main import app; print('OK')"
```

期待出力: `OK`

- [ ] **Step 4: コミットする**

```bash
git add static/js/viewer.js backend/templates/viewer.html
git commit -m "refactor: viewer.html のインライン JS を static/js/viewer.js に抽出する"
```

---

## 完了確認

- [ ] **全テストとカバレッジ確認**

```bash
pytest -v --cov --cov-report=term-missing 2>&1 | tail -30
```

期待出力: 全テスト PASSED、カバレッジ 80% 以上

- [ ] **lint チェック**

```bash
ruff check .
```

期待出力: エラーなし
