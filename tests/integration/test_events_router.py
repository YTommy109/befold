import pytest


def test_events_endpoint_exists(client):
    # SSE エンドポイントが存在し、接続できることを確認
    # TestClient は SSE をストリーミングしないため、接続確立のみ検証
    with client.stream("GET", "/events") as response:
        assert response.status_code == 200
        assert "text/event-stream" in response.headers["content-type"]
