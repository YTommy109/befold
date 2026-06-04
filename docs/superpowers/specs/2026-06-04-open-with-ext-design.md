# 設計書：`.mmd` / `.mermaid` ファイルの「このアプリで開く」対応

**日付:** 2026-06-04
**ブランチ:** feat/open_with_ext

## 概要

mmdview を macOS の「このアプリケーションで開く」対象として登録し、`.mmd` および `.mermaid` ファイルをダブルクリックまたは「Open With」で開けるようにする。

対応シナリオ：
1. **アプリ未起動時にファイルを開く** — `sys.argv[1]` でパスを受け取る
2. **アプリ起動済みの状態でファイルを開く** — Apple Events (`kAEOpenDocuments`) で受け取る

## アーキテクチャ

```
Finder でファイルをダブルクリック
        │
        ├─ アプリ未起動 → macOS が app バンドルを起動
        │                    → sys.argv[1] にファイルパスが入る
        │
        └─ アプリ起動済み → macOS が kAEOpenDocuments Apple Event を送信
                             → NSAppleEventManager のハンドラーが受け取る
                             → watch_service.set_file() + window.reload()
```

## 変更ファイル一覧

| ファイル | 変更種別 | 内容 |
|---|---|---|
| `mmdview.spec` | 変更 | `CFBundleDocumentTypes` を `info_plist` に追加 |
| `pyproject.toml` | 変更 | `pyobjc-framework-Cocoa` を依存に追加 |
| `backend/apple_events.py` | 新規 | Apple Events ハンドラーモジュール |
| `backend/app.py` | 変更 | `sys.argv` チェック・ハンドラー登録・ダイアログフィルター更新 |
| `tests/unit/test_apple_events.py` | 新規 | ユニットテスト |

## 詳細設計

### 1. `mmdview.spec` — `CFBundleDocumentTypes` の追加

```python
info_plist={
    'NSHighResolutionCapable': True,
    'CFBundleShortVersionString': '0.2.2',
    'CFBundleDocumentTypes': [
        {
            'CFBundleTypeName': 'Mermaid Diagram',
            'CFBundleTypeExtensions': ['mmd', 'mermaid'],
            'CFBundleTypeRole': 'Viewer',
            'LSHandlerRank': 'Owner',
        }
    ],
},
```

`LSHandlerRank: Owner` により、mmdview がこれらの拡張子の優先ハンドラーとして登録される。

### 2. `pyproject.toml` — 依存追加

```toml
dependencies = [
    ...
    "pyobjc-framework-Cocoa>=10.0; sys_platform == 'darwin'",
]
```

`pywebview` が macOS 上で pyobjc を使うが、直接依存として明示することでバンドル時の漏れを防ぐ。`sys_platform == 'darwin'` 条件付きで Linux CI への影響を避ける。

### 3. `backend/apple_events.py`（新規）

```python
import struct
from collections.abc import Callable
from Foundation import NSObject, NSURL
from AppKit import NSAppleEventManager

_kCoreEventClass = struct.unpack(">I", b"aevt")[0]
_kAEOpenDocuments = struct.unpack(">I", b"odoc")[0]
_keyDirectObject  = struct.unpack(">I", b"----")[0]

class _OpenFileHandler(NSObject):
    _callback: Callable[[str], None] | None = None

    def handleOpenDocuments_withReplyEvent_(self, event, reply):
        desc = event.paramDescriptorForKeyword_(_keyDirectObject)
        for i in range(1, desc.numberOfItems() + 1):
            raw = desc.descriptorAtIndex_(i).stringValue()
            path = NSURL.URLWithString_(raw).path()
            if path and self._callback:
                self._callback(path)

def register_open_file_handler(callback: Callable[[str], None]) -> None:
    handler = _OpenFileHandler.alloc().init()
    handler._callback = callback
    mgr = NSAppleEventManager.sharedAppleEventManager()
    mgr.setEventHandler_andSelector_forEventClass_andEventID_(
        handler,
        "handleOpenDocuments:withReplyEvent:",
        _kCoreEventClass,
        _kAEOpenDocuments,
    )
```

**設計上の判断:**
- `import webview` はここに含めない（テスト分離）
- `_OpenFileHandler` インスタンスは `NSAppleEventManager` が保持するため GC されない
- ファイル URL (`file:///path/to/file.mmd`) を `NSURL` 経由で POSIX パスに変換する

### 4. `backend/app.py` の変更

#### 4-a. `main()` の起動時ファイルパス処理

```python
def main() -> None:
    import sys
    port = _find_free_port()
    state = _load_window_state()

    cli_file = sys.argv[1] if len(sys.argv) > 1 else None
    initial_file = cli_file or state.get("last_file")
    if initial_file:
        watch_service.set_file(initial_file)
```

既存の `state.get("last_file")` より `sys.argv[1]` を優先する。

#### 4-b. Apple Events ハンドラー登録

```python
    from backend.apple_events import register_open_file_handler

    def _on_open_file(path: str) -> None:
        watch_service.set_file(path)
        for win in webview.windows:
            win.evaluate_js("window.location.reload()")

    register_open_file_handler(_on_open_file)
```

`webview.start()` より前に呼び出すことで、起動直後の Apple Event も受け取れる。

#### 4-c. ファイルダイアログのフィルター更新

```python
file_types=("Mermaid files (*.mmd;*.mermaid)", "All files (*.*)"),
```

### 5. テスト

```python
# tests/unit/test_apple_events.py
import pytest
from unittest.mock import MagicMock, patch

pytest.importorskip("AppKit")
from backend.apple_events import _OpenFileHandler

def test_handler_calls_callback_with_posix_path():
    received: list[str] = []
    handler = _OpenFileHandler.alloc().init()
    handler._callback = received.append

    mock_url = MagicMock()
    mock_url.path.return_value = "/Users/user/test.mmd"

    mock_desc_item = MagicMock()
    mock_desc_item.stringValue.return_value = "file:///Users/user/test.mmd"

    mock_desc = MagicMock()
    mock_desc.numberOfItems.return_value = 1
    mock_desc.descriptorAtIndex_.return_value = mock_desc_item

    mock_event = MagicMock()
    mock_event.paramDescriptorForKeyword_.return_value = mock_desc

    with patch("backend.apple_events.NSURL") as mock_nsurl:
        mock_nsurl.URLWithString_.return_value = mock_url
        handler.handleOpenDocuments_withReplyEvent_(mock_event, None)

    assert received == ["/Users/user/test.mmd"]
```

CI（Linux）では `pytest.importorskip("AppKit")` により自動スキップ。

## エラーハンドリング

- `NSURL.URLWithString_(raw).path()` が `None` を返す場合（不正な URL）はスキップ（`if path and ...` で対処済み）
- `sys.argv[1]` が存在しないファイルを指す場合は `watch_service.set_file()` の既存エラー処理に委ねる

## テスト戦略

- macOS のみ実行: `pytest.importorskip("AppKit")` でガード
- Apple Events のハンドラー登録自体（`register_open_file_handler`）は統合テストの対象外（pywebview の起動が必要なため）
- `_OpenFileHandler` の変換ロジックはモックを使ってユニットテスト
