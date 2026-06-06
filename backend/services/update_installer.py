# backend/services/update_installer.py
"""アプリ内自動アップデートのインストール処理。"""

from __future__ import annotations

import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Literal

from backend.services.update_mount import mount_dmg
from backend.services.update_service import update_service

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
