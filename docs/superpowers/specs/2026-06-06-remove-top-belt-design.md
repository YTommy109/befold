---
title: 上部帯（toolbar）の削除とウィンドウタイトルへのファイル名表示
date: 2026-06-06
status: approved
---

## 概要

viewer 画面上部にあった toolbar（ファイル名表示 + 「別のファイルを開く」ボタン）を削除し、
描画エリアをウィンドウ全体に広げる。ファイル名は macOS 標準に従いウィンドウタイトルバーに表示する。

## 背景

- macOS アプリはファイル名をウィンドウタイトルに表示するのが標準慣行
- 「別のファイルを開く」ボタンは File メニューの "Open..." と重複しており不要
- toolbar を削除することで描画エリアが広がり、UI がシンプルになる

## 変更ファイル

### `backend/templates/viewer.html`

`<div class="toolbar">...</div>` ブロックを削除する。`.viewer` が body 全体を占有する。

### `static/css/style.css`

以下のルールを削除する：
- `.toolbar`
- `.filepath`
- `button`
- `button:hover`

### `backend/routers/html.py`

- `_pick_file()` 関数を削除
- `POST /open-file` ハンドラを削除
- `GET /` の `TemplateResponse` コンテキストから `filename` と `filepath` を削除

### `backend/app.py`

以下の3か所で `window.title = Path(path).name` を設定する：

1. `_activate_file(path, window)` — メニュー経由でファイルを開くとき
2. `_on_open_file(path)` — Apple Events（Finder からダブルクリック）でファイルを開くとき
3. 起動時の `initial_file` ロード直後（`webview.create_window` 呼び出しの後）

## スコープ外

- welcome.html の変更（ファイル未選択時の画面はそのまま）
- ウィンドウタイトルへのアプリ名付加（ファイル名のみ表示）
- タイトルバーの proxy icon 対応
