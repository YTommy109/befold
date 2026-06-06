# tests/unit/test_update_service.py
"""UpdateService クラスの単体テスト。"""

from __future__ import annotations

import os
from unittest.mock import MagicMock, patch

import pytest

from backend.services.update_service import _CURRENT_VERSION, UpdateService


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
    with patch(
        "backend.services.update_service.httpx.get",
        return_value=_make_github_response("v999.9.9", assets),
    ):
        result = svc.check_update()
    assert result["available"] is True
    assert result["version"] == "999.9.9"
    assert result["download_url"] == "https://example.com/test.dmg"


def test_check_update_最新バージョン(svc: UpdateService) -> None:
    with patch(
        "backend.services.update_service.httpx.get",
        return_value=_make_github_response(f"v{_CURRENT_VERSION}"),
    ):
        result = svc.check_update()
    assert result["available"] is False


def test_check_update_キャッシュが効く(svc: UpdateService) -> None:
    with patch(
        "backend.services.update_service.httpx.get", return_value=_make_github_response("v0.2.0")
    ) as mock_get:
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
