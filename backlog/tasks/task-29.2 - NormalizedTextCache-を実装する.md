---
id: TASK-29.2
title: NormalizedTextCache を実装する
status: To Do
assignee: []
created_date: '2026-07-16 12:10'
labels: []
dependencies: []
references:
  - docs/superpowers/plans/2026-07-16-normalized-text-cache.md
parent_task_id: TASK-29
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldKit に NormalizedTextCache 構造体を新規追加する。Data を受け取り、エンコーディング判定→デコード→CRLF/CR→LF 正規化→行インデックス構築を一括で行う。Sendable な struct として設計し、dataHash を保持する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 NormalizedTextCache(data:) が UTF-8/UTF-8 BOM/UTF-16 LE/BE/UTF-32 LE/BE/Shift_JIS/EUC-JP をデコードする
- [ ] #2 CRLF/CR が LF に正規化される
- [ ] #3 lineStartIndices が各行の先頭 String.Index を正確に指す
- [ ] #4 デコード不能データで TextEncodingError.decodeFailed を throw する
- [ ] #5 100MB 超のデータを拒否する
- [ ] #6 dataHash が Data のハッシュ値を保持する
- [ ] #7 テスト: エンコーディング×改行コードの組み合わせ、BOM 除去、空データ、サイズ超過、デコード失敗
<!-- AC:END -->
