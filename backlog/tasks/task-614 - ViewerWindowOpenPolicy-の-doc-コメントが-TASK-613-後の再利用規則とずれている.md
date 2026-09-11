---
id: TASK-614
title: ViewerWindowOpenPolicy の doc コメントが TASK-613 後の再利用規則とずれている
status: To Do
assignee: []
created_date: '2026-09-11 13:50'
updated_date: '2026-09-11 13:53'
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
- [ ] #1 `reusableController` の doc コメントが「種別の絞り込み（`acceptsReopen`）は全 disposition に掛かり、その後に disposition ごとの規則が続く」と読める構造になっている
- [ ] #2 「スライド窓の再利用規則は `.newWindow` と同じ」という記述が消え、「候補にならない」に置き換わっている
- [ ] #3 `scripts/check-doc-symbols.sh` と swiftlint がコメント変更後も通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
レビューの残りが届き、「関連」に書いた `remapController` の判定の重複は確定した（rename 分岐が `noteOpened(_:in:)` を迂回している）。対応は TASK-616 の AC に移したので、このタスクは doc コメントだけを直す。
<!-- SECTION:NOTES:END -->
