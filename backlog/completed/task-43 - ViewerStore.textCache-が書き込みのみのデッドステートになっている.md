---
id: TASK-43
title: ViewerStore.textCache が書き込みのみのデッドステートになっている
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-17 02:07'
updated_date: '2026-07-17 08:27'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore.swift:94 の `@ObservationIgnored private var textCache: NormalizedTextCache?` は apply() の2箇所(:345, :359)で代入されるのみで、読み取りがプロダクション・テスト・JSブリッジのどこにもない。ドキュメントコメント(:93)は「検索・同一内容スキップに使う」と述べるが、同一内容スキップは別プロパティ contentHash で実装済みで、全行検索パスは本ブランチで削除された(コメントも stale)。チャンクパスでは StringChunkReader が同じ cache を保持しているため、削除しても失われるものはない。最大 ~100MB の正規化テキストを MainActor 上に無駄にピン留めしている。

修正: textCache プロパティ・代入・stale コメントを削除する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 textCache プロパティと全代入・関連コメントが削除されビルド・全テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerStore.swift の textCache プロパティ宣言(:97-98)とドキュメントコメントを削除する\n2. apply() 内の textCache = cache 代入(:354, :369)を削除する\n3. swift build / swift test で全テスト確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
textCache プロパティ(:97-98)とドキュメントコメント、apply() 内の代入2箇所(旧:354,369)を削除。swift build 成功、swift test で全365件パス確認。単純化検討: 既存の contentHash による同一内容スキップ機構は temperCacheと独立して機能しており、textCache 削除は他コードパスに影響しないためそのまま削除で完結。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore.textCache プロパティおよび apply() 内の代入2箇所、stale なドキュメントコメントを削除した。textCache は書き込みのみでプロダクション・テスト・JSブリッジのどこからも読み取られておらず、同一内容スキップは既存の contentHash で実装済みのため削除して問題ない。swift build / swift test(365件)で検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
