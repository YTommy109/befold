---
id: TASK-29.2
title: NormalizedTextCache を実装する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 12:10'
updated_date: '2026-07-16 12:32'
labels: []
dependencies: []
references:
  - docs/superpowers/plans/2026-07-16-normalized-text-cache.md
parent_task_id: TASK-29
priority: high
ordinal: 3
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldKit に NormalizedTextCache 構造体を新規追加する。Data を受け取り、エンコーディング判定→デコード→CRLF/CR→LF 正規化→行インデックス構築を一括で行う。Sendable な struct として設計し、dataHash を保持する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 NormalizedTextCache(data:) が UTF-8/UTF-8 BOM/UTF-16 LE/BE/UTF-32 LE/BE/Shift_JIS/EUC-JP をデコードする
- [x] #2 CRLF/CR が LF に正規化される
- [x] #3 lineStartIndices が各行の先頭 String.Index を正確に指す
- [x] #4 デコード不能データで TextEncodingError.decodeFailed を throw する
- [x] #5 100MB 超のデータを拒否する
- [x] #6 dataHash が Data のハッシュ値を保持する
- [x] #7 テスト: エンコーディング×改行コードの組み合わせ、BOM 除去、空データ、サイズ超過、デコード失敗
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
TDD で実装する（実装計画 Task 1 に準拠）:
1. テストファイル NormalizedTextCacheTests.swift を作成
2. テストがコンパイルエラーで失敗することを確認
3. NormalizedTextCache.swift を実装
4. テストが全て通ることを確認
5. AC#5 のサイズ超過テストを追加・確認
6. コミット
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NormalizedTextCache を BefoldKit に追加。20 テスト全合格（swift test --filter NormalizedTextCacheTests）。SHA-256 ベースの dataHash、非空入力の空デコード結果を decodeFailed として扱うガードを追加。全 343 テスト合格を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
