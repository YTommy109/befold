# Auto-Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub Releases API を使って DMG をダウンロード・インストールし、アプリを自動アップグレードできるようにする。

**Architecture:** macOS メニューの「Check for Updates...」と起動時の htmx バナー経由でバージョン確認し、バックグラウンドダウンロード → DMG マウント → bash スクリプトによる差し替え → 再起動という流れで更新する。

**Tech Stack:** Python 3.12, FastAPI, pywebview, htmx, PyObjC (AppKit), httpx, hdiutil (macOS)

---

## ファイルマップ

| 操作 | パス |
|------|------|
| 作成 | `backend/version.py` |
| 作成 | `backend/services/update_service.py` |
| 作成 | `backend/services/update_mount.py` |
| 作成 | `backend/services/update_installer.py` |
| 作成 | `backend/routers/update.py` |
| 作成 | `backend/update_window.py` |
| 作成 | `backend/templates/update_dialog.html` |
| 作成 | `backend/templates/partials/update_banner.html` |
| 作成 | `backend/templates/partials/update_progress.html` |
| 作成 | `backend/templates/partials/update_idle.html` |
| 作成 | `tests/unit/test_update_service.py` |
| 作成 | `tests/unit/test_update_installer.py` |
| 修正 | `pyproject.toml` — bumpversion に version.py を追加 |
| 修正 | `backend/main.py` — update ルーターを登録 |
| 修正 | `backend/app.py` — setup_app_menu を呼び出す |
| 修正 | `backend/templates/base.html` — update バナー div を追加 |

---

## Task 1: backend/version.py と bumpversion 設定

**Files:**
- Create: `backend/version.py`
- Modify: `pyproject.toml`

- [ ] **Step 1: version.py を作成する**

```python
# backend/version.py
"""アプリケーションバージョン。bumpversion が自動更新する。"""

__version__ = "0.1.0"
```

- [ ] **Step 2: pyproject.toml の bumpversion に version.py を追加する**

`pyproject.toml` の `[[tool.bumpversion.files]]` セクション末尾に追加:

```toml
[[tool.bumpversion.files]]
filename = "backend/version.py"
search = '__version__ = "{current_version}"'
replace = '__version__ = "{new_version}"'
```

- [ ] **Step 3: import が通ることを確認する**

```bash
uv run python -c "from backend.version import __version__; print(__version__)"
```

期待出力: `0.1.0`

- [ ] **Step 4: コミット**

```bash
git add backend/version.py pyproject.toml
git commit -m "feat: backend/version.py を追加して bumpversion に組み込む"
```

---

## Task 2: update_service.py と単体テスト

**Files:**
- Create: `backend/services/update_service.py`
- Create: `tests/unit/test_update_service.py`

- [ ] **Step 1: テストを書く**

```python
# tests/unit/test_update_service.py
"""update_service のバージョンチェック機能の単体テスト。"""

from __future__ import annotations

import os
from unittest.mock import MagicMock, patch

import backend.services.update_service as svc


def _make_github_response(tag: str, assets: list[dict] | None = None) -> MagicMock:
    mock = MagicMock()
    mock.json.return_value = {"tag_name": tag, "assets": assets or []}
    mock.raise_for_status = MagicMock()
    return mock


def test_check_update_新バージョンあり():
    svc._cache["checked_at"] = None
    assets = [
        {"name": "mmdview-v999.9.9.dmg", "browser_download_url": "https://example.com/test.dmg"}
    ]
    mock_resp = _make_github_response("v999.9.9", assets)

    with patch("backend.services.update_service.httpx.get", return_value=mock_resp):
        result = svc.check_update()

    assert result["available"] is True
    assert result["version"] == "999.9.9"
    assert result["download_url"] == "https://example.com/test.dmg"


def test_check_update_最新バージョン():
    svc._cache["checked_at"] = None
    mock_resp = _make_github_response(f"v{svc._CURRENT_VERSION}")

    with patch("backend.services.update_service.httpx.get", return_value=mock_resp):
        result = svc.check_update()

    assert result["available"] is False


def test_check_update_キャッシュが効く():
    svc._cache["checked_at"] = None
    mock_resp = _make_github_response("v0.2.0")

    with patch("backend.services.update_service.httpx.get", return_value=mock_resp) as mock_get:
        svc.check_update()
        svc.check_update()

    assert mock_get.call_count == 1


def test_check_update_MMDVIEW_MOCK_DMG環境変数でモック結果を返す():
    with patch.dict(os.environ, {"MMDVIEW_MOCK_DMG": "/tmp/mmdview-test.dmg"}):
        result = svc.check_update()

    assert result["available"] is True
    assert result["version"] == "999.0.0"
    assert result["download_url"] is None


def test_get_download_state_MMDVIEW_MOCK_DMG環境変数でdone状態を返す():
    with patch.dict(os.environ, {"MMDVIEW_MOCK_DMG": "/tmp/mmdview-test.dmg"}):
        result = svc.get_download_state()

    assert result["status"] == "done"
    assert result["percent"] == 100
    assert result["dmg_path"] == "/tmp/mmdview-test.dmg"


def test_download_update_進捗更新(tmp_path):
    svc._download_state.update({"percent": 0, "status": "idle", "dmg_path": None})
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

    assert svc._download_state["status"] == "done"
    assert svc._download_state["percent"] == 100
    assert svc._download_state["dmg_path"] == str(dmg_dest)


def test_invalidate_cache_はキャッシュをクリアする():
    import time

    svc._cache["checked_at"] = time.monotonic()
    svc._cache["result"] = {"available": False, "version": "0.1.0", "download_url": None}

    svc.invalidate_cache()

    assert svc._cache["checked_at"] is None
    assert svc._cache["result"] is None
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
uv run pytest tests/unit/test_update_service.py -v 2>&1 | head -20
```

期待: `ModuleNotFoundError` または `ImportError`

- [ ] **Step 3: update_service.py を実装する**

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

_cache: dict = {"checked_at": None, "result": None}
_download_state: dict = {"percent": 0, "status": "idle", "dmg_path": None}
_logger = logging.getLogger(__name__)


def _is_newer(remote: str, current: str) -> bool:
    def to_tuple(v: str) -> tuple[int, ...]:
        return tuple(int(x) for x in v.split("."))

    return to_tuple(remote) > to_tuple(current)


def _find_dmg_url(assets: list[dict]) -> str | None:
    for asset in assets:
        if asset.get("name", "").endswith(".dmg"):
            return asset.get("browser_download_url")
    return None


def check_update() -> dict:
    """GitHub Releases API で最新バージョンを確認する（1時間TTLキャッシュ）。

    MMDVIEW_MOCK_DMG が設定されている場合は GitHub を呼ばずモック結果を返す。
    """
    if os.environ.get("MMDVIEW_MOCK_DMG"):
        return {"available": True, "version": "999.0.0", "download_url": None}
    now = time.monotonic()
    if _cache["checked_at"] and now - _cache["checked_at"] < _CACHE_TTL:
        return _cache["result"]
    try:
        resp = httpx.get(GITHUB_API_URL, timeout=5, follow_redirects=True)
        resp.raise_for_status()
        data = resp.json()
        tag = data["tag_name"].lstrip("v")
        result: dict = {
            "available": _is_newer(tag, _CURRENT_VERSION),
            "version": tag,
            "download_url": _find_dmg_url(data.get("assets", [])),
        }
    except Exception:
        result = {"available": False, "version": _CURRENT_VERSION, "download_url": None}
    _cache["checked_at"] = now
    _cache["result"] = result
    _logger.info("更新確認: available=%s version=%s", result["available"], result["version"])
    return result


def get_download_state() -> dict:
    """ダウンロード状態のコピーを返す。

    MMDVIEW_MOCK_DMG が設定されている場合はそのパスで完了状態を返す。
    """
    if mock_dmg := os.environ.get("MMDVIEW_MOCK_DMG"):
        return {"percent": 100, "status": "done", "dmg_path": mock_dmg}
    return dict(_download_state)


def _do_download(url: str, dest: Path | None = None) -> None:
    """実際のダウンロード処理（バックグラウンドスレッドで実行）。"""
    _download_state.update({"percent": 0, "status": "downloading", "dmg_path": None})
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
                        _download_state["percent"] = int(downloaded / total * 100)
        _download_state["status"] = "done"
        _download_state["dmg_path"] = str(dmg_path)
    except Exception:
        _logger.error("ダウンロード失敗: url=%s", url, exc_info=True)
        _download_state["status"] = "error"


def invalidate_cache() -> None:
    """更新確認キャッシュを無効化する。"""
    _cache["checked_at"] = None
    _cache["result"] = None


def download_update(url: str) -> None:
    """ダウンロードをバックグラウンドスレッドで開始する。"""
    if _download_state["status"] == "downloading":
        return
    threading.Thread(target=_do_download, args=(url,), daemon=True).start()
```

- [ ] **Step 4: テストがすべて通ることを確認する**

```bash
uv run pytest tests/unit/test_update_service.py -v
```

期待: 全テスト PASS

- [ ] **Step 5: コミット**

```bash
git add backend/services/update_service.py tests/unit/test_update_service.py
git commit -m "feat: update_service を追加する（GitHub API チェック・ダウンロード管理）"
```

---

## Task 3: update_mount.py と update_installer.py の単体テスト

**Files:**
- Create: `backend/services/update_mount.py`
- Create: `backend/services/update_installer.py`
- Create: `tests/unit/test_update_installer.py`

- [ ] **Step 1: テストを書く**

```python
# tests/unit/test_update_installer.py
"""update_installer と update_mount の単体テスト。"""

from __future__ import annotations

import os
import plistlib
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

import backend.services.update_installer as installer
import backend.services.update_mount as mount_module
import backend.services.update_service as svc


@pytest.fixture(autouse=True)
def reset_download_state():
    svc._download_state.update({"percent": 0, "status": "idle", "dmg_path": None})
    yield
    svc._download_state.update({"percent": 0, "status": "idle", "dmg_path": None})


def _make_plist_bytes(mount_point: str) -> bytes:
    data = {
        "system-entities": [
            {"dev-entry": "/dev/disk4"},
            {"dev-entry": "/dev/disk4s1", "content-hint": "Apple_partition_map"},
            {
                "dev-entry": "/dev/disk4s2",
                "content-hint": "Apple_HFS",
                "mount-point": mount_point,
            },
        ]
    }
    return plistlib.dumps(data)


def test_get_app_path_frozen環境():
    fake_exe = "/Applications/mmdview.app/Contents/MacOS/mmdview"
    with patch.object(sys, "frozen", True, create=True):
        with patch.object(sys, "executable", fake_exe):
            result = installer._get_app_path()
    assert result == Path("/Applications/mmdview.app")


def test_get_app_path_開発環境():
    with patch.object(sys, "frozen", False, create=True):
        result = installer._get_app_path()
    assert result is None


def test_write_updater_script_内容検証(tmp_path):
    app_path = Path("/Applications/mmdview.app")
    mount_point = Path("/Volumes/mmdview")
    new_app_src = Path("/Volumes/mmdview/mmdview.app")
    dmg_path = Path("/Users/user/Downloads/mmdview-update.dmg")
    script_path = tmp_path / "mmdview-updater.sh"

    with patch.object(installer, "_SCRIPT_PATH", script_path):
        result = installer._write_updater_script(app_path, mount_point, new_app_src, dmg_path)

    content = result.read_text()
    assert "hdiutil detach" in content
    assert f'open "{app_path}"' in content
    assert f'cp -R "{new_app_src}"' in content
    assert "sleep 3" in content
    assert f'rm -f "{dmg_path}"' in content


def test_mount_dmg_plist_パースで正しいマウントポイントを返す(tmp_path):
    dmg_file = tmp_path / "test.dmg"
    dmg_file.touch()
    mock_result = MagicMock()
    mock_result.stdout = _make_plist_bytes("/Volumes/mmdview")

    with patch("subprocess.run", return_value=mock_result):
        result = mount_module.mount_dmg(str(dmg_file))

    assert result == Path("/Volumes/mmdview")


def test_mount_dmg_hdiutil失敗時はNoneを返す(tmp_path):
    import subprocess

    dmg_file = tmp_path / "test.dmg"
    dmg_file.touch()
    error = subprocess.CalledProcessError(1, "hdiutil")

    with patch("subprocess.run", side_effect=[MagicMock(), error]):
        result = mount_module.mount_dmg(str(dmg_file))

    assert result is None


def test_mount_dmg_plistパース失敗時はNoneを返す(tmp_path):
    dmg_file = tmp_path / "test.dmg"
    dmg_file.touch()
    mock_result = MagicMock()
    mock_result.stdout = b"not valid plist data"

    with patch("subprocess.run", return_value=mock_result):
        result = mount_module.mount_dmg(str(dmg_file))

    assert result is None


def test_mount_dmg_mount_pointなしの場合はNoneを返す(tmp_path):
    dmg_file = tmp_path / "test.dmg"
    dmg_file.touch()
    data = {"system-entities": [{"dev-entry": "/dev/disk4"}]}
    mock_result = MagicMock()
    mock_result.stdout = plistlib.dumps(data)

    with patch("subprocess.run", return_value=mock_result):
        result = mount_module.mount_dmg(str(dmg_file))

    assert result is None


def test_mount_dmg_MMDVIEW_MOCK_DMG環境変数でモックマウントポイントを返す():
    with patch.dict(os.environ, {"MMDVIEW_MOCK_DMG": "/tmp/mmdview-test.dmg"}):
        with patch.object(Path, "mkdir"):
            with patch.object(Path, "exists", return_value=True):
                result = mount_module.mount_dmg("/tmp/mmdview-test.dmg")
    assert result == mount_module._MOCK_VOLUME


def test_install_update_dmgなしは_no_dmg_を返す():
    svc._download_state.update({"percent": 0, "status": "idle", "dmg_path": None})
    result = installer.install_update()
    assert result == "no_dmg"


def test_install_update_マウント失敗は_mount_failed_を返す(tmp_path):
    import subprocess

    dmg_file = tmp_path / "test.dmg"
    dmg_file.touch()
    svc._download_state.update({"percent": 100, "status": "done", "dmg_path": str(dmg_file)})
    error = subprocess.CalledProcessError(1, "hdiutil")

    with patch("subprocess.run", side_effect=[MagicMock(), error]):
        result = installer.install_update()

    assert result == "mount_failed"


def test_install_update_appなしは_no_app_を返す(tmp_path):
    dmg_file = tmp_path / "test.dmg"
    dmg_file.touch()
    svc._download_state.update({"percent": 100, "status": "done", "dmg_path": str(dmg_file)})
    plist_bytes = _make_plist_bytes("/Volumes/Test")
    mock_result = MagicMock()
    mock_result.stdout = plist_bytes

    with patch("subprocess.run", return_value=mock_result):
        with patch.object(Path, "glob", return_value=[]):
            result = installer.install_update()

    assert result == "no_app"


def test_install_update_開発環境では_not_frozen_を返す(tmp_path):
    dmg_file = tmp_path / "test.dmg"
    dmg_file.touch()
    svc._download_state.update({"percent": 100, "status": "done", "dmg_path": str(dmg_file)})
    plist_bytes = _make_plist_bytes("/Volumes/Test")
    mock_result = MagicMock()
    mock_result.stdout = plist_bytes

    with patch.object(sys, "frozen", False, create=True):
        with patch("subprocess.run", return_value=mock_result):
            with patch.object(Path, "glob", return_value=[Path("/Volumes/Test/mmdview.app")]):
                result = installer.install_update()

    assert result == "not_frozen"


def test_get_app_path_MMDVIEW_MOCK_FROZEN環境変数が設定されている場合モックパスを返す():
    with patch.dict(os.environ, {"MMDVIEW_MOCK_FROZEN": "1"}):
        with patch.object(Path, "mkdir"):
            result = installer._get_app_path()
    assert result == Path("/tmp/mmdview-mock.app")


def test_install_update_MMDVIEW_MOCK_FROZEN環境変数でフローを実行できる(tmp_path):
    dmg_file = tmp_path / "test.dmg"
    dmg_file.touch()
    svc._download_state.update({"percent": 100, "status": "done", "dmg_path": str(dmg_file)})
    plist_bytes = _make_plist_bytes("/Volumes/Test")
    mock_run_result = MagicMock()
    mock_run_result.stdout = plist_bytes
    script_path = tmp_path / "mmdview-updater.sh"

    with patch.dict(os.environ, {"MMDVIEW_MOCK_FROZEN": "1"}):
        with patch("subprocess.run", return_value=mock_run_result):
            with patch.object(Path, "glob", return_value=[Path("/Volumes/Test/mmdview.app")]):
                with patch.object(installer, "_SCRIPT_PATH", script_path):
                    with patch("subprocess.Popen") as mock_popen:
                        with patch("os._exit") as mock_os_exit:
                            installer.install_update()

    mock_os_exit.assert_called_once_with(0)
    mock_popen.assert_called_once()


def test_install_update_成功時はPopenを呼びos_exitする(tmp_path):
    dmg_file = tmp_path / "test.dmg"
    dmg_file.touch()
    svc._download_state.update({"percent": 100, "status": "done", "dmg_path": str(dmg_file)})
    plist_bytes = _make_plist_bytes("/Volumes/Test")
    mock_run_result = MagicMock()
    mock_run_result.stdout = plist_bytes
    fake_exe = "/Applications/mmdview.app/Contents/MacOS/mmdview"
    script_path = tmp_path / "mmdview-updater.sh"

    with patch("subprocess.run", return_value=mock_run_result):
        with patch.object(Path, "glob", return_value=[Path("/Volumes/Test/mmdview.app")]):
            with patch.object(sys, "frozen", True, create=True):
                with patch.object(sys, "executable", fake_exe):
                    with patch.object(installer, "_SCRIPT_PATH", script_path):
                        with patch("subprocess.Popen") as mock_popen:
                            with patch("os._exit") as mock_os_exit:
                                installer.install_update()

    mock_os_exit.assert_called_once_with(0)
    mock_popen.assert_called_once_with(["bash", str(script_path)])
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
uv run pytest tests/unit/test_update_installer.py -v 2>&1 | head -20
```

期待: `ModuleNotFoundError` または `ImportError`

- [ ] **Step 3: update_mount.py を実装する**

```python
# backend/services/update_mount.py
"""DMG マウント処理ヘルパー。"""

from __future__ import annotations

import logging
import os
import plistlib
import subprocess
from pathlib import Path

_MOCK_VOLUME = Path("/tmp/mmdview-mock-volume")
_logger = logging.getLogger(__name__)


def _mock_mount() -> Path:
    _MOCK_VOLUME.mkdir(parents=True, exist_ok=True)
    macos = _MOCK_VOLUME / "mmdview-mock.app" / "Contents" / "MacOS"
    macos.mkdir(parents=True, exist_ok=True)
    exe = macos / "mmdview-mock"
    if not exe.exists():
        exe.write_text("#!/bin/bash\n")
        exe.chmod(0o755)
    return _MOCK_VOLUME


def _parse_mount_point(stdout: bytes) -> Path | None:
    try:
        plist = plistlib.loads(stdout)
    except Exception:
        return None
    for entity in plist.get("system-entities", []):
        if "mount-point" in entity:
            return Path(entity["mount-point"])
    return None


def mount_dmg(dmg_path: str) -> Path | None:
    """DMG をマウントしてマウントポイントを返す。

    MMDVIEW_MOCK_DMG 設定時はモックを返す。quarantine 属性を事前に除去する。
    """
    if os.environ.get("MMDVIEW_MOCK_DMG"):
        return _mock_mount()
    subprocess.run(["xattr", "-d", "com.apple.quarantine", dmg_path], capture_output=True)
    try:
        result = subprocess.run(
            ["hdiutil", "attach", dmg_path, "-nobrowse", "-plist"],
            capture_output=True,
            check=True,
            timeout=60,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        _logger.warning("hdiutil attach 失敗: %s", e)
        if hasattr(e, "stderr") and e.stderr:
            _logger.warning("stderr: %s", e.stderr.decode(errors="replace"))
        return None
    return _parse_mount_point(result.stdout)
```

- [ ] **Step 4: update_installer.py を実装する**

```python
# backend/services/update_installer.py
"""アプリ内自動アップデートのインストール処理。"""

from __future__ import annotations

import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Literal

from backend.services import update_service
from backend.services.update_mount import mount_dmg

_SCRIPT_PATH = Path("/tmp/mmdview-updater.sh")
_logger = logging.getLogger(__name__)

InstallResult = Literal["ok", "no_dmg", "mount_failed", "no_app", "not_frozen"]


def _get_app_path() -> Path | None:
    """PyInstaller 環境での .app バンドルパスを返す。

    MMDVIEW_MOCK_FROZEN 環境変数が設定されている場合はローカルテスト用パスを返す。
    """
    if os.environ.get("MMDVIEW_MOCK_FROZEN"):
        mock_app = Path("/tmp/mmdview-mock.app")
        mock_app.mkdir(parents=True, exist_ok=True)
        return mock_app
    if not getattr(sys, "frozen", False):
        return None
    # sys.executable = /Applications/mmdview.app/Contents/MacOS/mmdview
    return Path(sys.executable).parent.parent.parent


def _write_updater_script(
    app_path: Path, mount_point: Path, new_app_src: Path, dmg_path: Path
) -> Path:
    """インストール用シェルスクリプトを /tmp に書き出す。"""
    script = (
        "#!/bin/bash\n"
        "sleep 3\n"
        f'rm -rf "{app_path}"\n'
        f'cp -R "{new_app_src}" "{app_path.parent}/"\n'
        f'hdiutil detach "{mount_point}" -quiet\n'
        f'rm -f "{dmg_path}"\n'
        f'open "{app_path}"\n'
    )
    _SCRIPT_PATH.write_text(script)
    _SCRIPT_PATH.chmod(0o755)
    return _SCRIPT_PATH


def install_update() -> InstallResult:
    """DMG をマウントして .app を差し替え、再起動スクリプトを実行する。"""
    dmg_path = update_service.get_download_state().get("dmg_path")
    _logger.debug("dmg_path=%s exists=%s", dmg_path, dmg_path and Path(dmg_path).exists())
    if not dmg_path or not Path(dmg_path).exists():
        return "no_dmg"
    _logger.info("mount_dmg 開始: %s", dmg_path)
    mount_point = mount_dmg(dmg_path)
    if mount_point is None:
        _logger.warning("mount_dmg 失敗")
        return "mount_failed"
    _logger.info("マウントポイント: %s", mount_point)
    apps = list(mount_point.glob("*.app"))
    _logger.info("DMG 内 .app 一覧: %s", apps)
    if not apps:
        return "no_app"
    app_path = _get_app_path()
    if app_path is None:
        return "not_frozen"
    script_path = _write_updater_script(app_path, mount_point, apps[0], Path(dmg_path))
    _logger.info("更新スクリプト: %s", script_path)
    subprocess.Popen(["bash", str(script_path)])
    # sys.exit() は ThreadPoolExecutor ワーカースレッドしか終了しないため
    # プロセス全体を即時終了する os._exit() を使う
    _logger.info("プロセスを終了してインストールスクリプトに引き渡す")
    os._exit(0)
```

- [ ] **Step 5: テストがすべて通ることを確認する**

```bash
uv run pytest tests/unit/test_update_installer.py -v
```

期待: 全テスト PASS

- [ ] **Step 6: コミット**

```bash
git add backend/services/update_mount.py backend/services/update_installer.py tests/unit/test_update_installer.py
git commit -m "feat: update_mount / update_installer を追加する（DMG マウント・インストール）"
```

---

## Task 4: backend/routers/update.py

**Files:**
- Create: `backend/routers/update.py`

- [ ] **Step 1: update.py を作成する**

```python
# backend/routers/update.py
"""アップデート確認・ダウンロード・インストールの API。"""

from __future__ import annotations

from fastapi import APIRouter
from fastapi.requests import Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from backend.paths import TEMPLATES_DIR
from backend.services import update_service
from backend.services.update_installer import install_update
from backend.version import __version__ as _CURRENT_VERSION

router = APIRouter(prefix="/api/update", tags=["update"])
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))


@router.get("/dialog", response_class=HTMLResponse)
def update_dialog(request: Request) -> HTMLResponse:
    result = update_service.check_update()
    return templates.TemplateResponse(
        request,
        "update_dialog.html",
        {
            "available": result["available"],
            "latest_version": result["version"],
            "current_version": _CURRENT_VERSION,
            "download_url": result["download_url"],
        },
    )


@router.get("/check", response_class=HTMLResponse)
def check_update(request: Request) -> HTMLResponse:
    result = update_service.check_update()
    if not result["available"]:
        return templates.TemplateResponse(request, "partials/update_idle.html", {})
    return templates.TemplateResponse(
        request,
        "partials/update_banner.html",
        {"version": result["version"], "download_url": result["download_url"]},
    )


@router.post("/download", response_class=HTMLResponse)
def start_download(request: Request) -> HTMLResponse:
    result = update_service.check_update()
    if result["download_url"]:
        update_service.download_update(result["download_url"])
    state = update_service.get_download_state()
    return templates.TemplateResponse(
        request,
        "partials/update_progress.html",
        {"percent": state["percent"], "status": state["status"]},
    )


@router.get("/progress", response_class=HTMLResponse)
def get_progress(request: Request) -> HTMLResponse:
    state = update_service.get_download_state()
    return templates.TemplateResponse(
        request,
        "partials/update_progress.html",
        {"percent": state["percent"], "status": state["status"]},
    )


@router.post("/install", response_class=HTMLResponse)
def do_install(request: Request) -> HTMLResponse:
    result = install_update()
    if result == "not_frozen":
        return HTMLResponse(content="")
    state = {"percent": 100, "status": f"install_error:{result}"}
    return templates.TemplateResponse(
        request,
        "partials/update_progress.html",
        {"percent": 100, "status": state["status"]},
    )
```

- [ ] **Step 2: import が通ることを確認する**

```bash
uv run python -c "from backend.routers.update import router; print('ok')"
```

期待: `ok`

- [ ] **Step 3: コミット**

```bash
git add backend/routers/update.py
git commit -m "feat: update ルーターを追加する（/api/update/* エンドポイント）"
```

---

## Task 5: テンプレートを追加する

**Files:**
- Create: `backend/templates/update_dialog.html`
- Create: `backend/templates/partials/update_banner.html`
- Create: `backend/templates/partials/update_progress.html`
- Create: `backend/templates/partials/update_idle.html`

- [ ] **Step 1: partials ディレクトリを作成する**

```bash
mkdir -p backend/templates/partials
```

- [ ] **Step 2: update_dialog.html を作成する**

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="utf-8"/>
  <title>アップデート確認</title>
  <link rel="stylesheet" href="/static/css/style.css"/>
  <script src="https://unpkg.com/htmx.org@2.0.4" integrity="sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+" crossorigin="anonymous"></script>
</head>
<body>
<main style="padding: 2rem; max-width: 360px; margin: 0 auto; font-family: system-ui, sans-serif;">
  {% if not available %}
  <p style="font-size: 1.5rem; margin: 0">✓</p>
  <h2 style="margin: 0.5rem 0 0">最新バージョンです</h2>
  <p style="margin: 0.5rem 0 0; color: #666;">
    mmdview v{{ current_version }} は最新バージョンです。
  </p>
  {% else %}
  <div id="update-banner">
    <h2 style="margin: 0 0 1rem">v{{ latest_version }} が利用可能です</h2>
    <dl style="font-size: 0.9rem; margin: 0 0 1rem;">
      <div style="display: flex; gap: 0.5rem;">
        <dt style="color: #666; min-width: 3rem">現在</dt>
        <dd style="margin: 0">v{{ current_version }}</dd>
      </div>
      <div style="display: flex; gap: 0.5rem; margin-top: 0.25rem;">
        <dt style="color: #666; min-width: 3rem">最新</dt>
        <dd style="margin: 0">v{{ latest_version }}</dd>
      </div>
    </dl>
    {% if download_url %}
    <button
      hx-post="/api/update/download"
      hx-target="#update-banner"
      hx-swap="outerHTML"
      style="font-size: 0.9rem; width: 100%">
      ダウンロード
    </button>
    {% else %}
    <p style="font-size: 0.85rem; margin: 0; color: #666;">
      <a href="https://github.com/YTommy109/mmdview/releases/latest" target="_blank">
        GitHub リリースページ
      </a>からダウンロードしてください。
    </p>
    {% endif %}
  </div>
  {% endif %}
</main>
</body>
</html>
```

- [ ] **Step 3: update_banner.html を作成する**

```html
<div id="update-banner"
     style="padding: 0.5rem 0.75rem; font-size: 0.8rem; border-top: 1px solid #ccc; background: #f5f5f5;">
  <p style="margin: 0 0 0.4rem; font-weight: bold">v{{ version }} があります</p>
  <button
    hx-post="/api/update/download"
    hx-target="#update-banner"
    hx-swap="outerHTML"
    style="font-size: 0.75rem; width: 100%">
    ダウンロード
  </button>
</div>
```

- [ ] **Step 4: update_progress.html を作成する**

```html
<div id="update-banner"
     style="padding: 0.5rem 0.75rem; font-size: 0.8rem; border-top: 1px solid #ccc; background: #f5f5f5;"
     {% if status == "downloading" %}
     hx-get="/api/update/progress"
     hx-trigger="every 1s"
     hx-swap="outerHTML"
     {% endif %}>
  {% if status == "downloading" %}
    <p style="margin: 0 0 0.3rem">ダウンロード中...</p>
    <progress value="{{ percent }}" max="100" style="width: 100%"></progress>
    <p style="margin: 0.2rem 0 0; font-size: 0.7rem">{{ percent }}%</p>
  {% elif status == "done" %}
    <p style="margin: 0 0 0.4rem">ダウンロード完了</p>
    <button
      hx-post="/api/update/install"
      hx-target="#update-banner"
      hx-swap="outerHTML"
      style="font-size: 0.75rem; width: 100%">
      インストールして再起動
    </button>
  {% elif status == "error" %}
    <p style="margin: 0; color: #c00;">ダウンロードに失敗しました</p>
  {% elif status.startswith("install_error:") %}
    <p style="margin: 0; color: #c00;">インストールに失敗しました（{{ status.split(":")[-1] }}）</p>
    <p style="margin: 0.3rem 0 0; font-size: 0.7rem;">DMG ファイルを手動でマウントして更新してください。</p>
  {% endif %}
</div>
```

- [ ] **Step 5: update_idle.html を作成する**

```html
<div id="update-banner"
     hx-get="/api/update/check"
     hx-trigger="focus from:window"
     hx-swap="outerHTML">
</div>
```

- [ ] **Step 6: テンプレートが読み込めることを確認する**

```bash
uv run python -c "
from fastapi.templating import Jinja2Templates
from backend.paths import TEMPLATES_DIR
t = Jinja2Templates(directory=str(TEMPLATES_DIR))
print('update_dialog:', TEMPLATES_DIR / 'update_dialog.html')
print('exists:', (TEMPLATES_DIR / 'update_dialog.html').exists())
print('partials/update_idle:', (TEMPLATES_DIR / 'partials/update_idle.html').exists())
"
```

期待: `exists: True` が 2 行表示される

- [ ] **Step 7: コミット**

```bash
git add backend/templates/update_dialog.html backend/templates/partials/
git commit -m "feat: update 用テンプレートを追加する（ダイアログ・バナー・進捗）"
```

---

## Task 6: backend/update_window.py

**Files:**
- Create: `backend/update_window.py`

- [ ] **Step 1: update_window.py を作成する**

```python
# backend/update_window.py
"""更新確認ダイアログウィンドウの管理。"""

from __future__ import annotations

import logging
import threading

import webview

from backend.services import update_service

_logger = logging.getLogger(__name__)

HOST = "127.0.0.1"

_update_win: webview.Window | None = None
_menu_target: object | None = None  # NSObject の GC 防止のためモジュールスコープで保持

try:
    from AppKit import (  # ty: ignore[unresolved-import]
        NSApplication,  # type: ignore[import]
        NSMenuItem,  # type: ignore[import]
    )
    from AppKit import (  # ty: ignore[unresolved-import]
        NSObject as _NSObject,  # type: ignore[import]
    )

    class _UpdateMenuTarget(_NSObject):  # type: ignore[misc]
        """Check for Updates... メニュー項目のアクションターゲット。"""

        def checkForUpdates_(self, sender: object) -> None:
            # webview.create_window() はメインスレッドから呼ぶと即時描画されないため
            # バックグラウンドスレッドで呼び出す必要がある
            threading.Thread(
                target=open_update_dialog,
                args=(self._port,),  # type: ignore[attr-defined]
                daemon=True,
            ).start()

    class _MenuInstaller(_NSObject):  # type: ignore[misc]
        """メインスレッドでメニュー項目を挿入するヘルパー。"""

        def install_(self, _: object) -> None:
            main_menu = NSApplication.sharedApplication().mainMenu()
            if main_menu is None or main_menu.numberOfItems() == 0:
                return
            app_menu = main_menu.itemAtIndex_(0).submenu()
            if app_menu is None:
                return
            sep = NSMenuItem.separatorItem()
            item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                "Check for Updates...", "checkForUpdates:", ""
            )
            item.setTarget_(_menu_target)
            app_menu.insertItem_atIndex_(sep, 1)
            app_menu.insertItem_atIndex_(item, 2)

    _APPKIT_AVAILABLE = True

except ImportError:
    _APPKIT_AVAILABLE = False


def open_update_dialog(port: int) -> None:
    """更新確認ダイアログを開く。すでに開いていれば何もしない。"""
    global _update_win
    if _update_win is not None:
        return
    update_service.invalidate_cache()
    url = f"http://{HOST}:{port}/api/update/dialog"
    win = webview.create_window(
        title="アップデート確認",
        url=url,
        width=400,
        height=260,
        resizable=False,
    )
    if win is None:
        return

    def _on_closed() -> None:
        global _update_win
        _update_win = None

    win.events.closed += _on_closed
    _update_win = win


def setup_app_menu(port: int) -> None:
    """macOS アプリケーションメニューに「Check for Updates...」を追加する。

    webview.start(func=...) のコールバックから呼び出す。
    """
    global _menu_target
    try:
        _menu_target = _UpdateMenuTarget.alloc().init()
        _menu_target._port = port  # type: ignore[attr-defined]
        installer = _MenuInstaller.alloc().init()
        installer.performSelectorOnMainThread_withObject_waitUntilDone_("install:", None, True)
    except Exception as e:
        _logger.warning("メニュー設定に失敗しました: %s", e)
```

- [ ] **Step 2: import が通ることを確認する**

```bash
uv run python -c "from backend.update_window import setup_app_menu, open_update_dialog; print('ok')"
```

期待: `ok`（AppKit が使えない環境でも ImportError にならないこと）

- [ ] **Step 3: コミット**

```bash
git add backend/update_window.py
git commit -m "feat: update_window を追加する（macOS メニュー統合）"
```

---

## Task 7: 統合 — main.py / app.py / base.html

**Files:**
- Modify: `backend/main.py`
- Modify: `backend/app.py`
- Modify: `backend/templates/base.html`

- [ ] **Step 1: main.py に update ルーターを登録する**

`backend/main.py` を以下のように編集する（`from backend.routers import events, html` の行を変更）:

```python
import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from backend.paths import STATIC_DIR
from backend.routers import events, html, update
from backend.services.event_bus import event_bus


@asynccontextmanager
async def lifespan(app: FastAPI):
    event_bus.set_loop(asyncio.get_event_loop())
    yield


app = FastAPI(lifespan=lifespan)
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
app.include_router(html.router)
app.include_router(events.router)
app.include_router(update.router)
```

- [ ] **Step 2: app.py に setup_app_menu を追加する**

`backend/app.py` の `webview.start(menu=menu)` の行を変更する。

変更前:
```python
    webview.start(menu=menu)
```

変更後:
```python
    from backend.update_window import setup_app_menu

    webview.start(menu=menu, func=lambda: setup_app_menu(port))
```

- [ ] **Step 3: base.html に update バナー div を追加する**

`backend/templates/base.html` の `<body>` タグ直後に update バナー div を追加する。

変更前:
```html
<body>
  {% block content %}{% endblock %}
</body>
```

変更後:
```html
<body>
  <div id="update-banner"
       hx-get="/api/update/check"
       hx-trigger="load, focus from:window"
       hx-swap="outerHTML">
  </div>
  {% block content %}{% endblock %}
</body>
```

- [ ] **Step 4: サーバーが起動できることを確認する**

```bash
uv run task server &
sleep 2
curl -s http://127.0.0.1:8000/api/update/check | head -5
kill %1
```

期待: `<div id="update-banner"` を含む HTML が返ること

- [ ] **Step 5: 全テストが通ることを確認する**

```bash
uv run pytest -v
```

期待: 全テスト PASS、カバレッジ 80% 以上

- [ ] **Step 6: コミット**

```bash
git add backend/main.py backend/app.py backend/templates/base.html
git commit -m "feat: auto-upgrade を main.py / app.py / base.html に統合する"
```
