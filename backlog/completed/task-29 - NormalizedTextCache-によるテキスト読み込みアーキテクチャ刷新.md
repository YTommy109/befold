---
id: TASK-29
title: NormalizedTextCache によるテキスト読み込みアーキテクチャ刷新
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 12:09'
updated_date: '2026-07-16 13:29'
labels: []
dependencies: []
references:
  - docs/superpowers/specs/2026-07-16-normalized-text-cache-design.md
  - docs/superpowers/plans/2026-07-16-normalized-text-cache.md
priority: high
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LineChunkReader のバイトレベル一体処理を NormalizedTextCache（全量デコード＋改行正規化キャッシュ）+ StringChunkReader（String スライス）に分離する。v1.7.0 以降のバグ連鎖（TASK-20〜26）の根本原因を構造的に解消する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 行指向テキスト（csv/code）が NormalizedTextCache → StringChunkReader 経由でチャンク表示される
- [x] #2 CRLF/CR が LF に正規化され、チャンク境界で改行が消失しない
- [x] #3 UTF-16/UTF-32 の行指向ファイルがチャンク読み込みに対応する
- [x] #4 同一内容のファイル再保存で再描画されない（ハッシュ比較によるスキップ）
- [x] #5 LineChunkReader および関連する不要コードが削除される
- [x] #6 検索バーが DOM 全量構築ではなく表示済み範囲のみ検索する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
全サブタスク(29.1〜29.6)完了に伴う統合確認。swift test(345件、Integration/FileWatcher含む)/npx jest(185件)/webview-smoke いずれもパス。#1,#2,#3: NormalizedTextCacheTests/StringChunkReaderTests/ViewerStoreChunkTests で CR・CRLF正規化、UTF-16/UTF-32/レガシーエンコーディングのチャンク読込、行分割を確認。#4: ViewerStore.apply() の dataHash 比較スキップ実装(task-29.4で導入、当時366テスト通過で検証済み)を再確認。#5: LineChunkReader はソースツリーから削除済み(.build生成物のみ残存、task-29.5/commit 68d1d75)。#6: task-29.6でloadAllLinesForSearchを削除し表示範囲内検索へ移行、WKWebView実機検証済み(commit 8a014b1)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LineChunkReader のバイトレベル一体処理を NormalizedTextCache(全量デコード+改行正規化キャッシュ)+ StringChunkReader(Stringスライス)に分離するアーキテクチャ刷新を完了。TASK-20〜26 のバグ連鎖(チャンク境界の改行消失、世代カウンタ不整合、二重デコード、検索フリーズ等)を構造的に解消。6サブタスク(データフロー文書化→NormalizedTextCache実装→StringChunkReader実装→ViewerStore統合→LineChunkReader削除→検索の表示範囲内化)を順に完了し、最終的に全345 Swiftテスト・185 Jestテスト・WebViewスモークが通過することを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
