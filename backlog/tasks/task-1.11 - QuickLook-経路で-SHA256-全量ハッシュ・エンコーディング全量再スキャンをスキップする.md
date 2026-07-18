---
id: TASK-1.11
title: QuickLook 経路で SHA256 全量ハッシュ・エンコーディング全量再スキャンをスキップする
status: To Do
assignee: []
created_date: '2026-07-18 13:41'
updated_date: '2026-07-18 13:42'
labels: []
dependencies:
  - TASK-1.8
parent_task_id: TASK-1
priority: medium
type: enhancement
ordinal: 1150
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
パフォーマンスレビュー（2026-07-18）で発見（推奨）。(1) NormalizedTextCache.dataHash（:30-33）の SHA256.hash(data:) は ViewerStore.apply() のライブリロード同一内容スキップ専用（ViewerStore.swift:268,282）で、1回描画の QuickLook では 100MB 全走査が純粋な無駄。(2) TextEncoding のフォールバック（TextEncoding.swift:112, :73）は『UTF-8 デコード不可 かつ 先頭8KBのレガシー判定でも未確定』のときのみ NSString.stringEncoding を 100MB 全体に実行し、該当すると QuickLook 応答が秒単位まで伸びうる。QuickLook 経路では dataHash をスキップし、エンコーディング判定窓を先頭 N バイトに制限する。task-1.8 の先頭打ち切り読込と併せて対応するのが自然。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 静的1回読込（QuickLook）経路で dataHash 計算が行われない
- [ ] #2 エンコーディング判定のフォールバック全量スキャンが先頭Nバイトに制限される
- [ ] #3 アプリ本体のライブリロード同一内容スキップに回帰がない
<!-- AC:END -->
