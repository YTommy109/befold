---
id: TASK-590
title: サイドバーの delegate 配線を構造で担保する（必須引数化と Kind→request 表への統一）
status: To Do
assignee: []
created_date: '2026-09-05 02:48'
updated_date: '2026-09-06 09:40'
labels:
  - sidebar
dependencies: []
priority: medium
type: task
ordinal: 855000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-586 で注入クロージャを `FileListViewDelegate` へ畳んだ結果、担保が 2 箇所で弱くなった。

1. 削除した `let onToggleSlideMode` は非 optional で、doc に「既定値を持たせない。渡し忘れが『押しても何も起きないボタン』へ静かに倒れる」と書かれていた。いまは表示切り替えのトグルすべてが `weak var delegate: FileListViewDelegate?` 経由で、`FileListView` / `SidebarHeaderView` に明示 init が無いため memberwise init の暗黙 `= nil` により `FileListView(model: m)` がコンパイルも描画も通り、`perform(_:)` が全要求を捨てる。本番（`ViewerWindowAssembler`）とテスト 7 箇所は delegate を渡しているので観測されたバグではなく、外れたガード。

2. 畳み込みが 1 層手前で止まっている。`SidebarHeaderControls` はトグルごとの optional クロージャ（`onToggleLayoutMode` / `onToggleChangedFilesOnly`）を持ち続け、`SidebarHeaderView` が `{ perform(.toggleLayoutMode) }` 等で埋めている。`SidebarDisplayChangeRoutingTests.allDisplayChangesReachDelegate` は 4 リテラルを `header.perform(change)` へ直接流すので、この 2 クロージャの配線は通らない（2 つを入れ替えても、片方を `{}` にしても全テストが通る）。TASK-586 AC#4 は実態より強い。overflow 側は `(SidebarOverflowItem.Kind) -> Void` を 1 本発行して `displayChange(for:)` 表をテストする形で既に閉じているので、ボタン側も同じ形に揃える。

/code-review high（2026-09-05）の指摘。TASK-593.1 でスライドモードを撤去したため、対象は表示 4 値のトグルのみ（スライドボタンは存在しない）で、`SidebarDisplayRequest` の包みも `SidebarDisplayChange` へ畳まれている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `FileListView` と `SidebarHeaderView` は delegate を既定値の無い必須引数で受け、delegate を省いた生成がコンパイルエラーになる（保持は weak のまま）
- [ ] #2 `SidebarHeaderControls` はトグルごとのクロージャを持たず、押されたコントロールの Kind を 1 本のクロージャで発行する
- [ ] #3 ヘッダーの各コントロール Kind → `SidebarDisplayChange` の対応表がテストで固定され、対応を入れ替えるとテストが落ちる
- [ ] #4 `SidebarHeaderView.perform` が private に戻っている
- [ ] #5 TASK-586 AC#4 の記述が、この担保の実態に合わせて更新されている
<!-- AC:END -->
