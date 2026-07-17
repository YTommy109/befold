---
id: TASK-43
title: ViewerStore.textCache が書き込みのみのデッドステートになっている
status: To Do
assignee: []
created_date: '2026-07-17 02:07'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore.swift:94 の `@ObservationIgnored private var textCache: NormalizedTextCache?` は apply() の2箇所(:345, :359)で代入されるのみで、読み取りがプロダクション・テスト・JSブリッジのどこにもない。ドキュメントコメント(:93)は「検索・同一内容スキップに使う」と述べるが、同一内容スキップは別プロパティ contentHash で実装済みで、全行検索パスは本ブランチで削除された(コメントも stale)。チャンクパスでは StringChunkReader が同じ cache を保持しているため、削除しても失われるものはない。最大 ~100MB の正規化テキストを MainActor 上に無駄にピン留めしている。

修正: textCache プロパティ・代入・stale コメントを削除する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 textCache プロパティと全代入・関連コメントが削除されビルド・全テストが通る
<!-- AC:END -->
