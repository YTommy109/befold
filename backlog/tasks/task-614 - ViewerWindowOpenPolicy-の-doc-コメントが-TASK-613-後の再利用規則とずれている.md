---
id: TASK-614
title: ViewerWindowOpenPolicy の doc コメントが TASK-613 後の再利用規則とずれている
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-09-11 13:50'
updated_date: '2026-09-11 14:33'
labels: []
dependencies: []
ordinal: 804000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-613 のコードレビュー（/code-review high）で確定した指摘。コードは正しく、規則の唯一の説明箇所であるコメントだけが実装とずれている。

`BefoldApp/befold/App/ViewerWindowOpenPolicy.swift` の `reusableController` の doc コメント（コード参照）:
- 「`.newWindow` / `.slide`: … スライド窓は器が違うだけで、再利用の規則は `.newWindow` と同じ」と書いてあるが、TASK-613 後はスライド窓は disposition に関係なく候補から常に除外される（`candidates.filter(\.kind.acceptsReopen)` が switch の手前にある）。「規則が同じ」ではなく「そもそも候補にならない」。
- `acceptsReopen` の箇条書きを `.currentTab` の項の直後に挟んだため、`.currentTab` だけの規則に読める。実際は `.newTab` の重複抑止にも効く。

次に再利用規則を触る人がこのコメントを信じると、`.newTab` にも絞り込みが効いていることを見落とす。コメントの「箇条書きは disposition ごと、種別の絞り込みはその手前で全 disposition に掛かる」という構造に直す。

関連（レビューで未検証のまま残った単純化の候補）: `ViewerWindowSessionSync.remapController` が `controller.kind.isRestorable` を rename 分岐で 2 回、`noteOpened(_:in:)` で 1 回と別々に判定している。1 箇所に畳めるかは着手時に見る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `reusableController` の doc コメントが「種別の絞り込み（`acceptsReopen`）は全 disposition に掛かり、その後に disposition ごとの規則が続く」と読める構造になっている
- [x] #2 「スライド窓の再利用規則は `.newWindow` と同じ」という記述が消え、「候補にならない」に置き換わっている
- [x] #3 `scripts/check-doc-symbols.sh` と swiftlint がコメント変更後も通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. `reusableController` の doc コメントを 2 段構成に書き直す: (a) 種別の絞り込み(`acceptsReopen`)は disposition に関係なく全経路へ掛かる、(b) そのあとに disposition ごとの規則が続く。
2. 「スライド窓の再利用規則は `.newWindow` と同じ」を「候補にならない」へ差し替える。
3. `scripts/check-doc-symbols.sh` と swiftlint で確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
レビューの残りが届き、「関連」に書いた `remapController` の判定の重複は確定した（rename 分岐が `noteOpened(_:in:)` を迂回している）。対応は TASK-616 の AC に移したので、このタスクは doc コメントだけを直す。

doc コメントのみ。`reusableController` を「種別の絞り込み（`acceptsReopen`）が disposition に関係なく先に掛かる → そのあと disposition ごとの規則」という 2 段構成に書き直し、「スライド窓の再利用規則は `.newWindow` と同じ」を「そもそも候補にならない（`.currentTab` でも `.newTab` の重複抑止でも選ばれない）」へ差し替えた。`acceptsReopen` の記述は `.currentTab` の箇条書きから外へ出し、全 disposition に掛かることが読めるようにした。

検証（実測）: `scripts/check-doc-symbols.sh` exit=0、`swiftlint befold/App/ViewerWindowOpenPolicy.swift` 指摘 0 件、`swift test` 2007 tests passed。`/swiftlint-baseline` の origin/main 差分は「真の新規」「解消したもの」とも空。

Description の「関連」にあった `remapController` の判定の重複は Notes のとおり TASK-616 の AC #3 で対応した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`ViewerWindowOpenPolicy.reusableController` の doc コメントを TASK-613 後の実装（種別の絞り込みが全 disposition に先立って掛かる）に合わせて書き直した。コード変更なし。`scripts/check-doc-symbols.sh` と swiftlint、`swift test`（2007 件）で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
