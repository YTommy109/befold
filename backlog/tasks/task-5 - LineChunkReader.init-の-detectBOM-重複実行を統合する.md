---
id: TASK-5
title: LineChunkReader.init の detectBOM 重複実行を統合する
status: To Do
assignee: []
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/207
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #207 から移行。LineChunkReader.init が detectBOM を呼んだ後、else 分岐で detectEncoding を呼ぶが、detectEncoding 内部で detectBOM を再実行する。さらに isChunkableEncoding も BOM をスキャンしており、同じプローブを最大 3 回走査している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 detectEncoding を一度だけ呼んでエンコーディングを得る形に統合されている
<!-- AC:END -->
