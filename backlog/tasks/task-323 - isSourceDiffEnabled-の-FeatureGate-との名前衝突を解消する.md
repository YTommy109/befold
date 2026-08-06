---
id: TASK-323
title: isSourceDiffEnabled の FeatureGate との名前衝突を解消する
status: To Do
assignee: []
created_date: '2026-08-05 16:08'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: low
type: chore
ordinal: 510000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

FeatureGate.swift:55 の static var isSourceDiffEnabled（ビルドゲート: dev ビルドでのみ true）と、ViewerWindowController+Diff.swift:58 のインスタンスプロパティ isSourceDiffEnabled（ユーザー設定の表示 ON/OFF）が完全に同名で、1 つの識別子が 2 つの異なる意味を持っている。

リスク: ViewerWindowController 内の将来の編集で、ビルドゲートを見るつもりが無修飾の参照でインスタンス側に解決される（逆も同様）。また (gate) スコープ判定のための grep ベースのゲート監査（CLAUDE.md のコミット規約）でも呼び出し箇所の分類を誤る。

修正: ユーザー設定側を isDiffDisplayOn / showsDiff 等、意味が区別できる名前へリネームする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ビルドゲートとユーザー設定のプロパティ名が区別できる名前になっている
- [ ] #2 rg で isSourceDiffEnabled を検索したとき、FeatureGate 側の参照だけがヒットする
<!-- AC:END -->
