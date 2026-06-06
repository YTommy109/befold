from pathlib import Path
from unittest.mock import MagicMock, patch


def test_load_window_states_returns_empty_on_oserror():
    """WINDOW_STATE_FILE が存在するが read_text() が OSError を投げる場合、
    空リストを返すことを確認する。"""
    import backend.app as app_module

    fake_path = MagicMock(spec=Path)
    fake_path.exists.return_value = True
    fake_path.read_text.side_effect = OSError("Permission denied")

    with patch.object(app_module, "WINDOW_STATE_FILE", fake_path):
        result = app_module._load_window_states()

    assert result == []


def test_load_window_states_returns_empty_when_file_absent():
    """WINDOW_STATE_FILE が存在しない場合、空リストを返すことを確認する。"""
    import backend.app as app_module

    fake_path = MagicMock(spec=Path)
    fake_path.exists.return_value = False

    with patch.object(app_module, "WINDOW_STATE_FILE", fake_path):
        result = app_module._load_window_states()

    assert result == []


def test_load_window_states_backward_compat_with_dict():
    """旧形式（辞書）の JSON が保存されている場合、リストに変換して返すことを確認する。"""
    import json

    import backend.app as app_module

    old_state = {"x": 200, "y": 150, "width": 1280, "height": 800, "last_file": "/a/foo.mmd"}

    fake_path = MagicMock(spec=Path)
    fake_path.exists.return_value = True
    fake_path.read_text.return_value = json.dumps(old_state)

    with patch.object(app_module, "WINDOW_STATE_FILE", fake_path):
        result = app_module._load_window_states()

    assert len(result) == 1
    assert result[0]["x"] == 200
    assert result[0]["file"] == "/a/foo.mmd"
