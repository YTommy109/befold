---
id: TASK-272
title: フォルダー表示中も不可視の WebView が再描画され続ける
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-03 15:22'
updated_date: '2026-08-04 00:58'
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
- [x] #1 フォルダー一覧の表示中に監視対象ファイルが更新されても、不可視の WebView で再描画が走らない
- [x] #2 ファイル表示へ戻った時点で最新の内容が 1 度で反映される（取りこぼしがない）
- [x] #3 大きめのファイルを外部から連続更新しながらフォルダーを操作し、修正前後のメインスレッド占有を実測して Notes に残す
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ADR 0002 の段 5。可視性の判定は macOS の NSWindowOcclusionStateVisible（windowDidChangeOcclusionState）が正式な手段。不可視の間は更新をコアレスし、可視化時に 1 度だけ適用する。

## 実装（2026-08-04・ADR 0002 段 5）

可視性を ViewerRenderer.isVisible として状態に持ち（ホストの ViewerWebView が毎回の更新で流し込む）、不可視の間は updateContent を行わない。描画済みミラー（rendered）も更新しないため、見える状態へ戻ると SwiftUI が最新の値で updateNSView を呼び直し、抑止した更新が 1 回に畳まれる。設定の反映（倍率・フォント・検索オプション）は不可視でも通す。

## 実測 1: CPU 時間の増分（2MB の Markdown を外部から 15 回書き換え・約 9 秒間・フォルダー行を選んだ状態）
WebKit の子プロセスを含むプロセス群の CPU 時間:
| | 1 回目 | 2 回目 |
|---|---|---|
| 抑止なし | 1.91 秒 | 1.94 秒 |
| 抑止あり | 1.36 秒 | 1.36 秒 |

約 29% 減。

## 実測 2: メインスレッド占有（sample 6 秒）
| | total | idle | busy | applyRender |
|---|---|---|---|---|
| 抑止なし | 4923 | 4646 | 277 | 4 |
| 抑止あり | 4986 | 4740 | 246 | 0 |

**起票時の想定と違った点**: 「大きなファイルの保存のたびに不可視 WebView で完全な再レイアウトが走り、CPU とファンを使い続ける」という形の負荷は再現しなかった。WKWebView は不可視だとレンダリング自体を回さないため（Apple の Work When Visible の記述とも整合）、メインスレッド占有は 5% 前後で変化しない。減ったのは Swift 側の更新処理と WebKit への受け渡しぶんで、上記の CPU 時間差がそれにあたる。

## テスト
ViewerRendererVisibilityTests（3 件）: 不可視中は描画もミラー更新もしない / 可視へ戻ると最新の内容 1 回で反映される / 既定は可視（QuickLook など可視性を渡さない利用者を壊さない）。swift test 1037 tests green、swiftlint 新規警告なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
可視性を ViewerRenderer.isVisible として持ち、フォルダー一覧を重ねている間の再描画を止めた。2MB の Markdown を 15 回外部更新する実測で、WebKit を含む CPU 時間の増分が 1.91/1.94 秒 → 1.36/1.36 秒（約 29% 減）。ただし起票時に想定した「メインスレッドを使い続ける」形の負荷は再現せず（WKWebView は不可視だと描画を回さない）、メインスレッド占有は 5% 前後で不変。可視へ戻った時点で最新の内容が 1 回で反映されることをテストで固定。
<!-- SECTION:FINAL_SUMMARY:END -->
