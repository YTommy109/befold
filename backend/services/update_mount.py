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
