# mmdview 改善計画 設計ドキュメント

**日付:** 2026-06-05
**ブランチ:** `refactor/improve`
**スコープ:** バグ修正 → ファイル開く処理の統一 → スレッド安全性

---

## 背景

コードレビューで発見された以下の問題を解消する。

| ID | 分類 | 概要 |
|----|------|------|
| C1 | バグ | `/open-file` エンドポイントが `recent_files_service.add()` を呼ばない |
| C3 | バグ | `_pick_file()` のファイルタイプフィルタが `*.mmd;*.md`（他経路は `*.mmd;*.mermaid`）|
| C4 | バグ | 起動時の `initial_file` が `recent_files_service` に追加されない |
| C5 | バグ | `_load_window_state` が `OSError` を捕捉しない |
| C6 | スレッド安全性 | `_update_win` の check-then-assign にロックがない |
| C7 | スレッド安全性 | `EventBus.notify()` が list 反復中に `unsubscribe()` で変更されうる |

**対象外:** Open Recent メニューの静的スナップショット問題（pywebview の制約、今回は修正しない）

---

## 実装方針

1 ブランチ（`refactor/improve`）上に 4 つのコミットを段階的に積む。
各コミット後にテストが通ることを確認してから次に進む。

---

## コミット 1: C5 修正 — `_load_window_state` の OSError 捕捉

### 変更ファイル

- `backend/app.py`
- `tests/unit/test_window_state.py`（新規）

### 変更内容

```python
# backend/app.py:26
# 変更前
except (json.JSONDecodeError, KeyError):

# 変更後
except (json.JSONDecodeError, KeyError, OSError):
```

### 追加テスト

```python
# tests/unit/test_window_state.py
def test_load_window_state_returns_default_on_permission_error(tmp_path):
    # WINDOW_STATE_FILE が存在するが read_text() が OSError を投げる場合、
    # デフォルト値を返すことを検証
```

---

## コミット 2: ファイル開く処理の統一 — C1・C3・C4 解消

### 問題の根本原因

ファイルを開く 4 経路がそれぞれ独立して実装されており、抜け漏れが生じていた。

| 経路 | `recent_files.add()` | `set_file()` | reload |
|------|----------------------|--------------|--------|
| Apple Events (`_on_open_file`) | ✅ | ✅ | 全 window（thread） |
| File > Open (`_open_file_from_menu`) | ✅ | ✅ | 指定 window |
| File > Open Recent (`_open_recent`) | ✅ | ✅ | 指定 window |
| HTML `/open-file` | **❌ C1** | ✅ | HX-Redirect |

### 変更ファイル

- `backend/app.py`
- `backend/routers/html.py`
- `tests/integration/test_html_router.py`

### 変更内容

**1. `_activate_file` ヘルパーを `backend/app.py` に追加**

```python
def _activate_file(path: str, window: webview.Window) -> None:
    recent_files_service.add(path)
    watch_service.set_file(path)
    window.evaluate_js("window.location.reload()")
```

**2. `_open_file_from_menu` と `_open_recent` が `_activate_file` を使用**

```python
def _open_file_from_menu(window: webview.Window) -> None:
    result = window.create_file_dialog(
        FileDialog.OPEN,
        allow_multiple=False,
        file_types=("Mermaid files (*.mmd;*.mermaid)", "All files (*.*)"),
    )
    if result:
        _activate_file(result[0], window)

# _build_open_recent_menu 内の _open_recent
def _open_recent(path: str) -> None:
    _activate_file(path, window)
```

**3. `html.py` の `/open-file` エンドポイント（C1・C3 解消）**

```python
from backend.services.recent_files_service import recent_files_service
from backend.services.watch_service import watch_service

# _pick_file() のファイルタイプフィルタを統一（C3 解消）
file_types=("Mermaid files (*.mmd;*.mermaid)", "All files (*.*)"),

async def open_file() -> Response:
    path = _pick_file()
    if path:
        recent_files_service.add(path)   # C1 解消
        watch_service.set_file(path)
    return Response(headers={"HX-Redirect": "/"})
```

> **設計注記:** `html.py` の `open_file` は `window` オブジェクトを持たないため
> `_activate_file` を直接使わず `evaluate_js` の代わりに HX-Redirect を使う。
> この差分は意図的なもの（経路固有のリロード方式）として残す。

**4. 起動時 `initial_file`（C4 解消）**

```python
# backend/app.py main() 内
initial_file = (sys.argv[1] if len(sys.argv) > 1 else None) or state.get("last_file")
if initial_file:
    recent_files_service.add(initial_file)   # 追加
    watch_service.set_file(initial_file)
```

### 修正テスト

```python
# tests/integration/test_html_router.py

# fixture: recent_files_service のシングルトンをテスト間でリセット
@pytest.fixture(autouse=True)
def reset_recent_files_service():
    from backend.services.recent_files_service import recent_files_service
    recent_files_service.clear()
    yield
    recent_files_service.clear()

def test_open_file_sets_file_and_redirects(client, tmp_path):
    # 既存の watch_service.get_path() 検証に加えて
    from backend.services.recent_files_service import recent_files_service
    assert str(f) in recent_files_service.get()   # recent_files への追加を検証
```

**C4 のテストについて:** `initial_file` の処理は `main()` 内部にあり、`webview.start()` を伴うため単体テストが困難。コードレビューで確認済みの 1 行追加（`recent_files_service.add(initial_file)`）はコードインスペクションで担保する。

---

## コミット 3: C6 修正 — `_update_win` の競合状態

### 変更ファイル

- `backend/update_window.py`
- `tests/unit/test_update_window.py`

### 変更内容

```python
import threading

_update_win: webview.Window | None = None
_update_win_lock = threading.Lock()          # 追加

def open_update_dialog(port: int) -> None:
    global _update_win
    with _update_win_lock:                   # ロックで保護
        if _update_win is not None:
            return
        update_service.invalidate_cache()
        url = f"http://{HOST}:{port}/api/update/dialog"
        win = webview.create_window(...)
        if win is None:
            return

        def _on_closed() -> None:
            global _update_win
            with _update_win_lock:           # クローズ時も同じロック
                _update_win = None

        win.events.closed += _on_closed
        _update_win = win
```

### 追加テスト

```python
def test_open_update_dialog_concurrent_calls_create_one_window():
    # 2 スレッドから同時に open_update_dialog() を呼んでも
    # webview.create_window() が 1 回しか呼ばれないことを検証
```

---

## コミット 4: C7 修正 — `EventBus` のスナップショット反復

### 変更ファイル

- `backend/services/event_bus.py`
- `tests/unit/test_event_bus.py`

### 変更内容

```python
def notify(self, event: str = "reload") -> None:
    if self._loop is None:
        return
    for q in list(self._listeners):        # list() でスナップショットを作成
        self._loop.call_soon_threadsafe(q.put_nowait, event)
```

`list(self._listeners)` は GIL 保護された単一操作でコピーを生成するため、
反復中に `unsubscribe()` が呼ばれても元のリストへの変更は影響しない。

### 追加テスト

```python
def test_notify_during_unsubscribe_does_not_raise():
    # notify() の反復中に別スレッドが unsubscribe() を呼んでも
    # RuntimeError が発生せず、既存リスナーに通知が届くことを検証
```

---

## 変更ファイル一覧

| ファイル | 変更種別 | コミット |
|----------|----------|----------|
| `backend/app.py` | 修正 | 1, 2 |
| `backend/routers/html.py` | 修正 | 2 |
| `backend/services/event_bus.py` | 修正 | 4 |
| `backend/update_window.py` | 修正 | 3 |
| `tests/unit/test_window_state.py` | 新規 | 1 |
| `tests/integration/test_html_router.py` | 修正 | 2 |
| `tests/unit/test_update_window.py` | 修正 | 3 |
| `tests/unit/test_event_bus.py` | 修正 | 4 |
