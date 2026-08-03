---
id: TASK-272
title: フォルダー表示中も不可視の WebView が再描画され続ける
status: To Do
assignee: []
created_date: '2026-08-03 15:22'
labels:
  - performance
dependencies: []
priority: medium
ordinal: 463000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review high で CONFIRMED。TASK-266 以前は、フォルダー選択中は ViewerWebView が階層から外れていたため、外部のファイル変更は反映先を持たなかった（ユーザーがそのファイルへ戻った時点で描画された）。現在は filePreview が opacity 0 で常駐するため、FileWatcher → ViewerStore → ViewerWebView のパイプラインが content/contentRevision を送り続ける。

大きな Mermaid / Markdown を外部エディタやビルドが書き換えている状況では、ユーザーがフォルダー行をクリックしているだけでも保存のたびに不可視の WebView で完全な再レイアウトが走る。誰も見ていない出力のために CPU を使い続ける。

## 方針
プレビュー対象がフォルダーの間は再描画を抑止（または合流）し、ファイルへ戻った時点で 1 度だけ流す。TASK-266 で得た「WebView を作り直さない」利得は維持したまま、不可視時の仕事だけを落とす。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 フォルダー一覧の表示中に監視対象ファイルが更新されても、不可視の WebView で再描画が走らない
- [ ] #2 ファイル表示へ戻った時点で最新の内容が 1 度で反映される（取りこぼしがない）
- [ ] #3 大きめのファイルを外部から連続更新しながらフォルダーを操作し、修正前後のメインスレッド占有を実測して Notes に残す
<!-- AC:END -->
