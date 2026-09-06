---
id: TASK-593.3
title: スライド窓の前後移動キーを実装する
status: To Do
assignee: []
created_date: '2026-09-06 09:25'
labels:
  - sidebar
  - slide-mode
dependencies:
  - TASK-593.2
documentation:
  - docs/superpowers/specs/2026-09-06-slide-window-design.md
parent_task_id: TASK-593
priority: medium
type: feature
ordinal: 861000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スライド窓で Space / ↓ が次のファイル、Backspace（delete）/ Shift+Space / ↑ が前のファイルへ移る。本文のスクロールはトラックパッド・マウスホイールのみで、キーは前後移動専用（ヒアリングで決定）。端では何もしない（周回しない）。

配線はスライド窓にだけ付ける `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`（前例: `SwipeHistoryMonitor`）。自窓が key window のときだけ扱い、窓が閉じたら外す。⌘ / ⌥ / ⌃ 付きは素通し（メニューのキー等価が勝つ）、first responder がテキスト入力（検索欄など）なら素通し。キー → 動作の対応は `SidebarKeyAction` と同じ純粋な表にして単体で測る。

隣の解決は `model.listSnapshot` をキー 1 回につき 1 度だけ読み（読むたびに再計算する。TASK-418）、`FileListSnapshot.next(after:)` / `previous(before:)` を `kind == .file` の行に当たるまで繰り返す（`next` はフォルダー行も返す。実測）。ファイルを開く経路は通常窓と同じ `ViewerWindowController+FileNavigation` を通し、履歴・タイトル・per-file の表示メモリを従来どおり効かせる。

JS 側の `spaceScroll` と `viewer-src/keyboard.ts` の矢印スクロール、PDF の `keyDown` は触らない。モニタが先に消費するので本文には届かない。

未確認の前提: WKWebView がフォーカスを持つ状態でローカルモニタが keyDown を先取りできるかは未実測。着手時に最初に実機で確かめ、取れなければ `NSWindow` サブクラスの `sendEvent(_:)` 上書きへ切り替える（判断を Implementation Notes に残す）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 スライド窓で Space と ↓ が次のファイル、Backspace と Shift+Space と ↑ が前のファイルを開く（Markdown・PDF・画像のいずれを表示中でも）
- [ ] #2 フォルダー行を飛ばし、絞り込み・不可視・変更のみ・ツリーの展開状態を反映した表示順で移動する（`FileListSnapshot` を組む純粋テスト）
- [ ] #3 最後のファイルで「次へ」、最初のファイルで「前へ」は何もしない
- [ ] #4 修飾キー付きのイベントと、テキスト入力中（検索欄）の Space / Backspace / ↑↓ は素通しされる（キー表のテスト）
- [ ] #5 通常のビューア窓ではキー割当が変わらない（Space のページ送り・サイドバーの Backspace で親へ、の既存テストが通る）
- [ ] #6 スライド窓を閉じたあとにモニタが残らない
- [ ] #7 native-app-design.md にスライド窓のキー表が記述されている
<!-- AC:END -->
