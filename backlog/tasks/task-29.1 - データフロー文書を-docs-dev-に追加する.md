---
id: TASK-29.1
title: データフロー文書を docs/dev に追加する
status: To Do
assignee: []
created_date: '2026-07-16 12:10'
labels: []
dependencies: []
references:
  - docs/superpowers/specs/2026-07-16-normalized-text-cache-design.md
parent_task_id: TASK-29
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
テキストファイルの読み込み〜表示に至るデータフローを記録する。現行フロー（LineChunkReader）と新フロー（NormalizedTextCache + StringChunkReader）の両方を図示し、サイズ制限・エンコーディング対応表を含める。実装に先立ち、現在のコードを確認して正確な内容を書く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 docs/dev/text-loading-dataflow.md が作成されている
- [ ] #2 現行フロー（LineChunkReader 経由）がコードと一致している
- [ ] #3 新フロー（NormalizedTextCache → StringChunkReader 経由）が設計書と一致している
- [ ] #4 サイズ制限表（バイナリ 50MB / 非行指向 10MB / 行指向 100MB）が記載されている
- [ ] #5 エンコーディング対応表（UTF-8/UTF-16/UTF-32/Shift_JIS 等の現行・新フロー比較）が記載されている
<!-- AC:END -->
