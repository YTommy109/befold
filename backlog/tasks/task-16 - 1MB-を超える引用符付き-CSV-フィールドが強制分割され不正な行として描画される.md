---
id: TASK-16
title: 1MB を超える引用符付き CSV フィールドが強制分割され不正な行として描画される
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:55'
updated_date: '2026-07-16 06:39'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/197'
priority: medium
type: bug
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
引用符付きフィールドが maxChunkBytes（1MB）を超える CSV 行は、LineChunkReader が引用符状態を維持したまま強制分割し inQuotes = false にリセットする。JS 側 parseCsv はチャンクをまたぐ状態を持たないため、1 つの論理行が 2 つの不正な行として描画される。トリガーの現実性は要判断。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 挙動が確認するテストが存在するか、既知の制限として設計ドキュメントに明記されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化検討: task-14 の contextStr 方式を CSV にも適用する案を検討したが、Swift→JS 間の新しい継続状態フラグ追加と appendChunk CSV 分岐へのマージロジック新設が必要で、既存の inQuotes リセット(連鎖的強制分割防止の安全策)も見直しが要る非自明な二重サイド変更になる。AC は「テストまたは既知の制限として文書化」のいずれかで足りるため、状態やロジックを増やさずに docs/superpowers/specs/2026-07-14-line-chunked-loading-design.md に既知の制限として明記する方針を採用した(ユーザー承認済み)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
1MB超の引用符付きCSVフィールドがLineChunkReaderの強制分割でinQuotesリセットされ、JS側parseCsvもチャンクをまたぐ引用符状態を持たないため2つの不正な行として描画される問題について、実修正ではなく既知の制限としてdocs/superpowers/specs/2026-07-14-line-chunked-loading-design.mdの「既知の制限」セクションに明記した(原因・inQuotesリセットの意図・JS側の欠如・対応する場合に必要な変更を記載)。grepで当該記述の存在を確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
