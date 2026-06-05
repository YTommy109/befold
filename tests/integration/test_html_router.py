from unittest.mock import MagicMock, patch

import pytest


@pytest.fixture(autouse=True)
def reset_watch_service():
    from backend.services.watch_service import watch_service

    watch_service.stop()
    watch_service._path = None
    yield
    watch_service.stop()
    watch_service._path = None


def test_index_shows_welcome_when_no_file(client):
    response = client.get("/")
    assert response.status_code == 200
    assert "ファイルを開く" in response.text


def test_index_shows_viewer_when_file_set(client, tmp_path):
    f = tmp_path / "test.mmd"
    f.write_text("graph TD\n    A --> B", encoding="utf-8")
    from backend.services.watch_service import watch_service

    watch_service.set_file(str(f))

    response = client.get("/")
    assert response.status_code == 200
    assert "graph TD" in response.text
    assert "test.mmd" in response.text


def test_open_file_sets_file_and_redirects(client, tmp_path):
    f = tmp_path / "diagram.mmd"
    f.write_text("graph LR\n    X --> Y", encoding="utf-8")

    with patch("backend.routers.html._pick_file", return_value=str(f)):
        response = client.post("/open-file")

    assert response.status_code == 200
    assert response.headers.get("HX-Redirect") == "/"
    from backend.services.watch_service import watch_service

    assert watch_service.get_path() == f


def test_open_file_does_nothing_when_cancelled(client):
    with patch("backend.routers.html._pick_file", return_value=None):
        response = client.post("/open-file")
    assert response.status_code == 200
    assert response.headers.get("HX-Redirect") == "/"


@patch("backend.routers.html.recent_files_service")
def test_open_file_adds_to_recent_files(mock_recent_svc, client, tmp_path):
    """POST /open-file はファイルを recent_files_service に追加しなければならない。"""
    f = tmp_path / "diagram.mmd"
    f.write_text("graph LR\n    X --> Y", encoding="utf-8")

    with patch("backend.routers.html._pick_file", return_value=str(f)):
        response = client.post("/open-file")

    assert response.status_code == 200
    mock_recent_svc.add.assert_called_once_with(str(f))


def test_pick_file_uses_mermaid_extension():
    """_pick_file() のファイルタイプフィルタは *.mermaid を使い *.md は使わない。"""
    import webview

    mock_window = MagicMock()
    mock_window.create_file_dialog.return_value = None

    with patch.object(webview, "windows", [mock_window]):
        from backend.routers.html import _pick_file

        _pick_file()

    file_types_str = mock_window.create_file_dialog.call_args.kwargs["file_types"][0]
    assert "*.mermaid" in file_types_str, f"*.mermaid not in filter: {file_types_str}"
    assert "*.md" not in file_types_str, (
        f"*.md should not be in Mermaid filter, got: {file_types_str}"
    )
