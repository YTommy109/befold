from pathlib import Path
from unittest.mock import MagicMock, patch


def test_load_window_state_returns_default_on_oserror():
    """WINDOW_STATE_FILE が存在するが read_text() が OSError を投げる場合、
    デフォルト値を返すことを確認する。"""
    import backend.app as app_module

    fake_path = MagicMock(spec=Path)
    fake_path.exists.return_value = True
    fake_path.read_text.side_effect = OSError("Permission denied")

    with patch.object(app_module, "WINDOW_STATE_FILE", fake_path):
        result = app_module._load_window_state()

    assert result == {"x": 100, "y": 100, "width": 1024, "height": 768, "last_file": None}
