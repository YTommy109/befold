---
id: TASK-47
title: TextEncoding のフォールバック全データスキャンで NUL バイトによる UTF-16 誤判定が起きる
status: To Do
assignee: []
created_date: '2026-07-17 05:10'
updated_date: '2026-07-17 05:22'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
detectAndDecodeText のフォールバックパスがファイル全体を sniffWindow として渡すため、8KB 以降に NUL バイトを含む Shift_JIS ファイル等が UTF-16 と誤分類される。また detectEncoding (公開 API) にはこのフォールバック自体がなく、2つの検出エントリポイント間でロバスト性が不一致。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 フォールバック時の NUL バイトチェックが全ファイルではなく適切な範囲に限定される
- [ ] #2 detectEncoding と detectAndDecodeText の両公開 API が同一のフォールバック戦略を共有する
- [ ] #3 先頭 8KB が ASCII で本文に NUL を含む Shift_JIS ファイルが正しく処理されることをテストで確認
<!-- AC:END -->
