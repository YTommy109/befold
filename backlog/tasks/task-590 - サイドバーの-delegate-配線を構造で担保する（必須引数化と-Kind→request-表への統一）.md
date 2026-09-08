---
id: TASK-590
title: サイドバーの delegate 配線を構造で担保する（必須引数化と Kind→request 表への統一）
status: Done
assignee:
  - '@claude'
created_date: '2026-09-05 02:48'
updated_date: '2026-09-08 10:15'
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
- [x] #1 `FileListView` と `SidebarHeaderView` は delegate を既定値の無い必須引数で受け、delegate を省いた生成がコンパイルエラーになる（保持は weak のまま）
- [x] #2 `SidebarHeaderControls` はトグルごとのクロージャを持たず、押されたコントロールの Kind を 1 本のクロージャで発行する
- [x] #3 ヘッダーの各コントロール Kind → `SidebarDisplayChange` の対応表がテストで固定され、対応を入れ替えるとテストが落ちる
- [x] #4 `SidebarHeaderView.perform` が private に戻っている
- [x] #5 TASK-586 AC#4 の記述が、この担保の実態に合わせて更新されている
- [x] #6 SidebarContextMenu も同じ形(weak var delegate の暗黙 = nil)なので、同じ必須引数 init を置く(兄弟箇所の同型の穴を残さない)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarHeaderControls: onToggleLayoutMode / onToggleChangedFilesOnly / onToggleFilter の 3 クロージャを撤去し、押されたボタンの SidebarHeaderControl.Kind を発行する onSelectControl 1 本にする(onSelectOverflowItem はそのまま)。action(for:) の switch も消える。
2. SidebarHeaderView: selectControl(_ kind:) を internal で足し、Kind → 動作の対応表(.layoutMode → .toggleLayoutMode / .changedFilesOnly → .toggleChangedFilesOnly / .filter → toggleFilter / .overflow → 何もしない。Menu が自前で開く)をここに 1 箇所で持つ。selectOverflowItem も internal にし、perform(_:) は private へ戻す。オーバーフロー側の displayChange(for:) は TASK-592 が動かすので触らない。
3. FileListView / SidebarHeaderView に明示 init(model:delegate:) を置き、delegate を既定値の無い必須引数にする(保持は weak var のまま)。FileListView 側は非 optional で受ける(prod は controller、テストは spy を渡している)。SidebarHeaderView 側は FileListView の weak 写しを受けるため optional 型だが既定値は無し。
4. SidebarDisplayChangeRoutingTests: perform 直呼びをやめ、header.selectControl(kind) → spy.displayChanges と header.selectOverflowItem(kind) → spy.displayChanges で Kind → SidebarDisplayChange の表を固定する(対応を入れ替えると落ちる)。.filter は delegate へ届かず transient.isFilterActive だけ動くことも測る。
5. TASK-586 AC#4 の文言を実態(4 種の表示切替が Kind → delegate の経路ごとテストで固定されている)に合わせて書き換える。
6. swift build / swift test / swiftlint ベースライン差分ゼロ / xcodegen 不要(新規ファイル無し)を確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
/review-design(2026-09-08)の結果。該当した項目は 3 と 9、他は非該当。
- 項目 3(兄弟箇所): FileListViewDelegate? を weak var で持つ SwiftUI ビューは FileListView / SidebarHeaderView / SidebarContextMenu の 3 つ(rg 'FileListViewDelegate?' で実測)。起票は前 2 つだけを名指ししていたが、SidebarContextMenu も明示 init が無く暗黙 = nil の memberwise init が生えている同型。1 箇所だけ塞ぐと同型の穴が残るので AC#6 として同じ扱いに含める。
- 項目 7(測るものと守るもの): ボタンの Kind → SidebarDisplayChange の表は SidebarHeaderView.selectControl(_:) の switch に 1 箇所で置き、SidebarHeaderControls には onSelectControl: selectControl をメソッド参照で渡す(包みクロージャを挟まない)。テストは selectControl(kind) → spy.displayChanges を測るので、テストが通らない配線は SwiftUI Button の中の onSelectControl(control.kind) 1 行だけになる。
- 項目 9(守らせるもの): AC#1 の『省くとコンパイルエラー』はテストでは書けないので、既定値の無い明示 init という『破りようのない構造』で担保する。FileListView.init は非 optional の FileListViewDelegate で受け、SidebarHeaderView / SidebarContextMenu は FileListView の weak 写しを受けるため optional 型だが既定値は置かない。
- 項目 10(行数・責務): 実測 FileListView グループ 335 行 / SidebarHeaderView 126 行 / SidebarHeaderControls 89 行。見積もりは +8 / +15 / -10 程度。プロトコル準拠の増加なし、注入クロージャは SidebarHeaderControls で 4 → 2 に減る、stored property の増加なし。
- 表の置き場: ボタン Kind には .filter(ローカル状態)と .overflow(Menu が自前で開く)が含まれるので、Kind → SidebarDisplayChange を全射にはできない。TASK-592 のようにモデル側へ寄せず、ビューの switch に置くのが妥当。

実装と検証(2026-09-08)。
- SidebarHeaderControls: onToggleLayoutMode / onToggleChangedFilesOnly / onToggleFilter と action(for:) を撤去し、onSelectControl: (SidebarHeaderControl.Kind) -> Void の 1 本にした。注入クロージャは 4 → 2 本(onSelectOverflowItem は残る)。
- SidebarHeaderView: selectControl(_:) に Kind → 動作の表を置いた(.layoutMode → .toggleLayoutMode / .changedFilesOnly → .toggleChangedFilesOnly / .filter → ローカルの開閉 / .overflow → 何もしない)。SidebarHeaderControls へはメソッド参照 onSelectControl: selectControl で渡し、包みクロージャを挟まない。perform(_:) は private に戻した。
- FileListView は init(model:delegate: FileListViewDelegate)(非 optional)、SidebarHeaderView / SidebarContextMenu は init(...delegate: FileListViewDelegate?) を明示し、いずれも既定値無し。実測: delegate を省いた FileListView(model:) / SidebarHeaderView(model:) / SidebarContextMenu(entry:model:) を置いた使い捨てファイルで swift build --build-tests が 'missing argument for parameter delegate in call' で落ちることを確認(ファイルは削除済み)。
- SidebarDisplayChangeRoutingTests: perform 直呼びをやめ、selectControl(kind) / selectOverflowItem(kind) → spy.displayChanges で表を固定。実測: selectControl の .layoutMode / .changedFilesOnly の右辺を入れ替えると 2 ケースが落ちる(差し戻し済み)。
- 検証: swift test 1914 tests in 313 suites passed / swiftformat --lint 全ターゲット 0 件 / swiftlint ベースライン差分ゼロ(origin/main 51 件 → HEAD 51 件、新規・解消ともゼロ)。
- docs/dev/native-app-design.md は更新不要と判断。FileListView を表の 1 行で扱うだけで、親子間の配線方式や init の形を記述していない(TASK-586 と同じ判断)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの delegate 配線を構造で担保した。FileListView / SidebarHeaderView / SidebarContextMenu に既定値の無い明示 init(model:delegate:) を置き、delegate を省いた生成はコンパイルエラーになる(使い捨てファイルで実測)。SidebarHeaderControls はトグルごとのクロージャをやめ、押されたボタンの Kind を onSelectControl 1 本で発行し、Kind → SidebarDisplayChange の表は SidebarHeaderView.selectControl(_:) に 1 箇所で持つ。perform(_:) は private へ戻した。SidebarDisplayChangeRoutingTests が selectControl / selectOverflowItem 経由で表を固定し、右辺を入れ替えると落ちることを実測。TASK-586 AC#4 の文言を実態に合わせた。検証: swift test 1914 件通過、swiftformat 0 件、swiftlint ベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
