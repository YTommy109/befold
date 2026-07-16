---
id: TASK-29
title: NormalizedTextCache によるテキスト読み込みアーキテクチャ刷新
status: To Do
assignee: []
created_date: '2026-07-16 12:09'
labels: []
dependencies: []
references:
  - docs/superpowers/specs/2026-07-16-normalized-text-cache-design.md
  - docs/superpowers/plans/2026-07-16-normalized-text-cache.md
priority: high
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LineChunkReader のバイトレベル一体処理を NormalizedTextCache（全量デコード＋改行正規化キャッシュ）+ StringChunkReader（String スライス）に分離する。v1.7.0 以降のバグ連鎖（TASK-20〜26）の根本原因を構造的に解消する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 行指向テキスト（csv/code）が NormalizedTextCache → StringChunkReader 経由でチャンク表示される
- [ ] #2 CRLF/CR が LF に正規化され、チャンク境界で改行が消失しない
- [ ] #3 UTF-16/UTF-32 の行指向ファイルがチャンク読み込みに対応する
- [ ] #4 同一内容のファイル再保存で再描画されない（ハッシュ比較によるスキップ）
- [ ] #5 検索バーが DOM 全量構築ではなく表示済み範囲のみ検索する
- [ ] #6 LineChunkReader および関連する不要コードが削除される
<!-- AC:END -->
