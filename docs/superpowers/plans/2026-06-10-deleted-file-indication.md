# 削除ファイル表示（"deleted" 検知 + タイトル + 背景）実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

<!-- derived-from ../specs/2026-06-10-watch-reload-fix-design.md -->

**Goal:** 監視中のファイルが削除・リネームされたとき、ウィンドウタイトルに ` (deleted)` を付加し背景をライトグレーに変更する。

**Architecture:** `_ChangeHandler` に `on_deleted` と `on_moved` 移動元チェックを追加し、`_fire()` がファイル不在時に `"deleted"` イベントを SSE 経由で送信する。フロントエンドは `document.title` 更新と `document.body.style.background` 変更で対応する。デバウンス機構がアトミックセーブ時の偽削除イベントを自動吸収する。

**Tech Stack:** Python 3.12+ / watchdog / threading.Timer / Jinja2 / native EventSource (JS)

---

## ファイル構成

- Modify: `backend/services/watch_service.py` — `_fire()`・`on_deleted`・`on_moved` 変更
- Modify: `backend/routers/html.py` — テンプレートコンテキストに `filename_json` 追加
- Modify: `backend/templates/viewer.html` — `_mmdFilename` 変数と "deleted" ハンドラ追加
- Modify: `tests/unit/test_watch_service.py` — 削除検知テスト 3 件追加
- Modify: `tests/integration/test_html_router.py` — filename レンダリングテスト追加

---

### Task 1: `_fire()` を "deleted" 対応に変更する

ファイルが存在しないとき `"reload"` ではなく `"deleted"` を送るよう `_fire()` を修正する。

**Files:**
- Modify: `backend/services/watch_service.py`
- Modify: `tests/unit/test_watch_service.py`

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_watch_service.py` の既存テストの末尾に追加する:

```python
def test_fire_notifies_deleted_when_file_missing(tmp_mmd):
    bus = _TrackingBus()
    handler = _ChangeHandler(tmp_mmd, bus, debounce=0.01)
    tmp_mmd.unlink()
    handler._fire()
    assert bus.notified == ["deleted"]
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `uv run pytest tests/unit/test_watch_service.py::test_fire_notifies_deleted_when_file_missing -v`
Expected: FAIL（`bus.notified == []` のまま、または `["reload"]` にならない）

- [ ] **Step 3: `_fire()` を修正する**

`backend/services/watch_service.py` の `_fire` メソッドを変更する:

変更前:
```python
    def _fire(self) -> None:
        if self._target.exists():
            self._bus.notify()
```

変更後:
```python
    def _fire(self) -> None:
        self._bus.notify("reload" if self._target.exists() else "deleted")
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `uv run pytest tests/unit/test_watch_service.py -v`
Expected: 全テスト PASS（既存テストも含む）

- [ ] **Step 5: コミット**

```bash
git add backend/services/watch_service.py tests/unit/test_watch_service.py
git commit -m "fix: ファイル不在時に _fire() が deleted イベントを送信するよう変更する"
```

---

### Task 2: `on_deleted` ハンドラを追加する

`FileDeletedEvent` が監視対象ファイルに対して届いたとき、デバウンス経由で `_maybe_notify` を呼ぶ。

**Files:**
- Modify: `backend/services/watch_service.py`
- Modify: `tests/unit/test_watch_service.py`

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_watch_service.py` の import 行を変更する:

```python
from watchdog.events import FileCreatedEvent, FileDeletedEvent, FileMovedEvent
```

テスト末尾に追加する:

```python
def test_handler_on_deleted_target_notifies_deleted(tmp_mmd):
    bus = _TrackingBus()
    handler = _ChangeHandler(tmp_mmd, bus, debounce=0.01)
    tmp_mmd.unlink()
    handler.on_deleted(FileDeletedEvent(str(tmp_mmd)))
    assert _wait_for_notify(bus)
    assert bus.notified == ["deleted"]
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `uv run pytest tests/unit/test_watch_service.py::test_handler_on_deleted_target_notifies_deleted -v`
Expected: FAIL（`on_deleted` が存在しないか、通知が来ない）

- [ ] **Step 3: `on_deleted` ハンドラを追加する**

`backend/services/watch_service.py` の `on_moved` メソッドの直後に追加する:

```python
    def on_deleted(self, event: FileSystemEvent) -> None:
        self._maybe_notify(event.src_path)
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `uv run pytest tests/unit/test_watch_service.py -v`
Expected: 全テスト PASS

- [ ] **Step 5: コミット**

```bash
git add backend/services/watch_service.py tests/unit/test_watch_service.py
git commit -m "feat: on_deleted ハンドラを追加してファイル削除を検知する"
```

---

### Task 3: `on_moved` にファイル移動元チェックを追加する

ファイルが別パスへ rename されたとき（`src_path == target`）も削除として検知する。

**Files:**
- Modify: `backend/services/watch_service.py`
- Modify: `tests/unit/test_watch_service.py`

- [ ] **Step 1: 失敗するテストを書く**

`tests/unit/test_watch_service.py` 末尾に追加する:

```python
def test_handler_on_moved_away_notifies_deleted(tmp_mmd, tmp_path):
    bus = _TrackingBus()
    handler = _ChangeHandler(tmp_mmd, bus, debounce=0.01)
    new_path = tmp_path / "renamed.mmd"
    tmp_mmd.rename(new_path)
    handler.on_moved(FileMovedEvent(str(tmp_mmd), str(new_path)))
    assert _wait_for_notify(bus)
    assert bus.notified == ["deleted"]
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `uv run pytest tests/unit/test_watch_service.py::test_handler_on_moved_away_notifies_deleted -v`
Expected: FAIL（移動元チェックがないため通知が来ない）

- [ ] **Step 3: `on_moved` を変更する**

`backend/services/watch_service.py` の `on_moved` メソッドを変更する:

変更前:
```python
    def on_moved(self, event: FileSystemEvent) -> None:
        # アトミックセーブは一時ファイルからの rename 置き換えとして届く
        self._maybe_notify(event.dest_path)
```

変更後:
```python
    def on_moved(self, event: FileSystemEvent) -> None:
        # アトミックセーブは一時ファイルからの rename 置き換えとして届く
        self._maybe_notify(event.dest_path)
        # ファイルが別パスへ移動された場合は削除として扱う
        self._maybe_notify(event.src_path)
```

- [ ] **Step 4: 全テストが通ることを確認する**

Run: `uv run pytest tests/unit/test_watch_service.py -v`
Expected: 全テスト PASS（既存の `test_handler_on_moved_to_target_notifies` も通ること）

- [ ] **Step 5: コミット**

```bash
git add backend/services/watch_service.py tests/unit/test_watch_service.py
git commit -m "feat: ファイルが移動された場合も deleted として検知する"
```

---

### Task 4: HTML テンプレートに filename を渡す

`viewer.html` で JavaScript からファイル名を参照できるよう、テンプレートコンテキストに `filename_json` を追加する。

**Files:**
- Modify: `backend/routers/html.py`
- Modify: `backend/templates/viewer.html`
- Modify: `tests/integration/test_html_router.py`

- [ ] **Step 1: 失敗するテストを書く**

`tests/integration/test_html_router.py` 末尾に追加する:

```python
def test_viewer_renders_filename_as_js_variable(client, tmp_path):
    f = tmp_path / "mydiagram.mmd"
    f.write_text("graph TD\n    A --> B", encoding="utf-8")
    from backend.services.window_registry import window_registry

    window_registry.create("w-fn-check", str(f))
    response = client.get("/?window_id=w-fn-check")
    assert response.status_code == 200
    assert 'var _mmdFilename = "mydiagram.mmd"' in response.text
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `uv run pytest tests/integration/test_html_router.py::test_viewer_renders_filename_as_js_variable -v`
Expected: FAIL（`_mmdFilename` が未定義）

- [ ] **Step 3: `html.py` に `filename_json` を追加する**

`backend/routers/html.py` の `return templates.TemplateResponse(request, "viewer.html", ...)` を変更する:

変更前:
```python
    return templates.TemplateResponse(
        request,
        "viewer.html",
        {"content": content, "window_id": window_id},
    )
```

変更後（先頭に `import json` を追加すること）:
```python
import json
```

```python
    return templates.TemplateResponse(
        request,
        "viewer.html",
        {"content": content, "window_id": window_id, "filename_json": json.dumps(path.name)},
    )
```

- [ ] **Step 4: `viewer.html` に `_mmdFilename` 変数を追加する**

`backend/templates/viewer.html` の `<script>` ブロック冒頭（`var _mmdZoom = 1;` の直前）に追加する:

```javascript
var _mmdFilename = {{ filename_json | safe }};
```

追加後の該当箇所:

```javascript
<script>
var _mmdFilename = {{ filename_json | safe }};
var _mmdZoom = 1;
var _mmdBaseScale = 0.75;
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `uv run pytest tests/integration/test_html_router.py -v`
Expected: 全テスト PASS

- [ ] **Step 6: コミット**

```bash
git add backend/routers/html.py backend/templates/viewer.html tests/integration/test_html_router.py
git commit -m "feat: viewer.html に _mmdFilename JS 変数を追加する"
```

---

### Task 5: "deleted" SSE イベントでタイトル更新・背景変更を実装する

`viewer.html` の EventSource ハンドラを拡張し、`"deleted"` 受信時に `document.title` と背景色を変更する。

**Files:**
- Modify: `backend/templates/viewer.html`
- Modify: `tests/integration/test_html_router.py`

- [ ] **Step 1: 失敗するテストを書く**

`tests/integration/test_html_router.py` 末尾に追加する:

```python
def test_viewer_has_deleted_sse_handler(client, tmp_path):
    f = tmp_path / "test.mmd"
    f.write_text("graph TD\n    A --> B", encoding="utf-8")
    from backend.services.window_registry import window_registry

    window_registry.create("w-del-handler", str(f))
    response = client.get("/?window_id=w-del-handler")
    assert response.status_code == 200
    assert "deleted" in response.text
    assert "#e8e8e8" in response.text
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `uv run pytest tests/integration/test_html_router.py::test_viewer_has_deleted_sse_handler -v`
Expected: FAIL（`#e8e8e8` が存在しない）

- [ ] **Step 3: EventSource ハンドラを更新する**

`backend/templates/viewer.html` 末尾の EventSource ブロックを変更する:

変更前:
```javascript
(function() {
  var es = new EventSource('/events?window_id={{ window_id }}');
  es.onmessage = function(e) {
    if (e.data === 'reload') location.reload();
  };
})();
```

変更後:
```javascript
(function() {
  var es = new EventSource('/events?window_id={{ window_id }}');
  es.onmessage = function(e) {
    if (e.data === 'reload') {
      location.reload();
    } else if (e.data === 'deleted') {
      document.title = _mmdFilename + ' (deleted)';
      document.body.style.background = '#e8e8e8';
    }
  };
})();
```

- [ ] **Step 4: 全テストが通ることを確認する**

Run: `uv run pytest tests/unit tests/integration -q`
Expected: 全テスト PASS、エラーなし

- [ ] **Step 5: コミット**

```bash
git add backend/templates/viewer.html tests/integration/test_html_router.py
git commit -m "feat: deleted SSE イベントでタイトルに (deleted) を付加し背景をグレーにする"
```
