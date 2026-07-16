---
id: TASK-2
title: エンコーディング検出ロジックを TextEncoding に単一情報源化する
status: To Do
assignee: []
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/202
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #202 から移行。3つの重複: (1) decodeText が detectEncoding の検出ロジックを再実装、(2) NUL パリティ計数が FileReading と TextEncoding に同一内容でインライン展開、(3) 先頭スニフ窓 8192 バイトが binarySniffLength と sniffLength の 2 定数に分裂。片側だけ変更すると全量読みとチャンク読みが静かに乖離するリスク。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 decodeText が detectEncoding に委譲している
- [ ] #2 NUL パリティ計数の共有ヘルパーが TextEncoding に一箇所で定義されている
- [ ] #3 先頭スニフ窓の定数が単一情報源になっている
<!-- AC:END -->
