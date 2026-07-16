---
id: TASK-29.1
title: データフロー文書を docs/dev に追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 12:10'
updated_date: '2026-07-16 12:26'
labels: []
dependencies: []
references:
  - docs/superpowers/specs/2026-07-16-normalized-text-cache-design.md
parent_task_id: TASK-29
priority: high
ordinal: 2
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
テキストファイルの読み込み〜表示に至るデータフローを記録する。現行フロー（LineChunkReader）と新フロー（NormalizedTextCache + StringChunkReader）の両方を図示し、サイズ制限・エンコーディング対応表を含める。実装に先立ち、現在のコードを確認して正確な内容を書く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 docs/dev/text-loading-dataflow.md が作成されている
- [x] #2 現行フロー（LineChunkReader 経由）がコードと一致している
- [x] #3 新フロー（NormalizedTextCache → StringChunkReader 経由）が設計書と一致している
- [x] #4 サイズ制限表（バイナリ 50MB / 非行指向 10MB / 行指向 100MB）が記載されている
- [x] #5 エンコーディング対応表（UTF-8/UTF-16/UTF-32/Shift_JIS 等の現行・新フロー比較）が記載されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. docs/dev/text-loading-dataflow.md を作成する
2. 現行フロー（LineChunkReader）をコードに基づいて正確に記述する
3. 新フロー（NormalizedTextCache + StringChunkReader）を設計書に基づいて記述する
4. サイズ制限表・エンコーディング対応表を含める
5. ビルド確認（文書のみなので swift build）
6. コミットする
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
docs/dev/text-loading-dataflow.md を作成した。現行フロー（ViewerStore.computeLoad → LineChunkReader のバイトレベル処理）と新フロー（NormalizedTextCache による全量デコード＋正規化 → StringChunkReader の String スライス）の両方を図示。サイズ制限表（バイナリ 50MB / 非行指向 10MB / 行指向 100MB）、エンコーディング対応表（UTF-8/16/32/Shift_JIS/EUC-JP の現行・新比較）、既存バグ TASK-20〜26 への影響表を含む。swift build で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
