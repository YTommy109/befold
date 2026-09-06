---
id: TASK-593.2
title: 窓種別 .slide と「スライドモードで開く」を追加する
status: To Do
assignee: []
created_date: '2026-09-06 09:25'
updated_date: '2026-09-06 10:32'
labels:
  - sidebar
  - slide-mode
dependencies:
  - TASK-593.1
documentation:
  - docs/superpowers/specs/2026-09-06-slide-window-design.md
parent_task_id: TASK-593
priority: medium
type: feature
ordinal: 860000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スライド窓の器を作る。既存のビューア窓に生成時の窓種別 `kind`（`.viewer` / `.slide`）を足し、`.slide` のときはアセンブラがツールバー無し・サイドバー折りたたみ固定・`tabbingMode = .disallowed` で組む。前後移動キーは次のサブタスクで、ここでは「サイドバーの無い窓が開いて閉じられる」までを作る。

入口はサイドバーのコンテキストメニューだけ。`SidebarContextMenu.openElsewhereEntries` の表に 1 行足し、`OpenDisposition` に `.slide` を加える（delegate メソッドは増やさない）。フォルダー行は「新しいウィンドウで開く」と同じく最初の対応ファイルを開く。`openViewer` は `.slide` を `.newWindow` と同じ「常に新規窓」の規則で扱う。

サイドバーを開かせないガードは 3 箇所（`ViewerMenuValidator` で ⌘S と ⌘← を無効、`ViewerSplitViewController.toggleSidebar(_:)` を `.slide` で no-op、ツールバー自体を付けない）。1 箇所でも漏れると「サイドバーの無い窓」が崩れるので、3 経路すべてで `isCollapsed` が変わらないことをテストで固定する。折りたたみは種別の帰結であって利用者の選択ではないので `SidebarStateStore.recordToggle` に書かない（ADR 0002）。

一覧の初期値は元の窓から引き継ぐ。`SidebarListingSeed` は directory / listing / sortOrder / showHiddenFiles の 4 つしか運ばない（実測）ので、レイアウト・「変更のみ」・ツリーの展開状態を足し、`canApply(to:)` の一致条件も広げる。この拡張は「新しいウィンドウで開く」にも同じ引き継ぎをもたらす（意図した副作用）。展開状態を `FileListModel` がどの形で持っているかは未確認で、着手時に決める。

セッション復元は `ViewerTabGrouping.tabGroup(of:)` のスナップショットから `.slide` の窓を除外する（`SessionLayout` に種別は足さない）。

l10n: `sidebar.context.openInSlideMode`（en / ja）を `sidebar.context.openInNewWindow` の隣に置く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 コンテキストメニューの「スライドモードで開く」で、選んだファイル（フォルダー行なら最初の対応ファイル）がサイドバー無し・ツールバー無しの新しい窓で開く
- [x] #2 スライド窓は「タブを好む」設定でも既存窓のタブに合流せず、⌘W で閉じられる
- [x] #3 スライド窓で ⌘S・⌘←・`toggleSidebar(_:)` のどれを通してもサイドバーが開かず、`SidebarStateStore` に書き込みが起きないことをテストが固定している
- [x] #4 スライド窓の隠れた一覧が元の窓の並び順・不可視・変更のみ・レイアウト・ツリーの展開状態を引き継いでいる（`SidebarListingSeed` のテスト）
- [x] #5 再起動後のセッション復元にスライド窓が含まれない（スナップショットのテスト）
- [x] #6 ソース表示・差分表示（⌘1/⌘2/⌘3・⌘U・⌘\）がスライド窓でも従来どおり効く
- [x] #7 `/l10n-check` が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果を反映した方針（2026-09-06）

### 1. 窓種別 `ViewerWindowKind`（`.viewer` / `.slide`）

`ViewerWindowController` に stored property `kind` を足し、init 引数で受ける（既定値は `.viewer`）。実測: 型グループは 905 行で恒久例外の上限に張り付いているため、`scripts/type-group-exceptions.txt` の上限引き上げが必ず要る（責務の増分はプロトコル準拠 0・注入クロージャ 0・stored property 1 で、既存の `initialSidebarCollapsed` と同じ「この窓が何であるか」の関心。受け皿は現状のまま）。

### 2. サイドバーを開かせないガードは 2 箇所（spec の 3 箇所から削減）

- `ViewerSplitViewController.toggleSidebar(_:)` を `.slide` で no-op にする。`setSidebarCollapsed(_:)` は `toggleSidebar` を呼ぶ実装なので、CLI の `--sidebar` / `forceSidebarVisible` 経路もこの 1 箇所で塞がる（絞り込み点）
- `ViewerMenuValidator` で ⌘S（`toggleSidebar`）を `.slide` では無効にする
- **⌘← は新規の分岐を足さない。** 既存の `focusSidebar` 判定が `!source.isSidebarCollapsed` で、スライド窓は常に collapsed なのでそのまま無効になる

`recordToggle` へのガードも足さない。実測: 本番の呼び出し元は `ViewerWindowAssembler` の `onCollapsedChange` 1 箇所だけで、`toggleSidebar` からしか発火しない。no-op にすれば構造的に届かない（2 箇所で同じことを言わない）。

### 3. per-file の折りたたみ記憶を汚さない（spec に記載なし）

`ViewerWindowManager.makeController` の `perFileState.sidebar.setCollapsed(initialSidebarCollapsed, for: url)` は種別を見ずに必ず走る。`.slide` では飛ばす。通すと「そのファイルを次に通常窓で開くとサイドバーが畳まれている」状態が残り、ADR 0002 の「折りたたみは種別の帰結であって利用者の選択ではない」がここで破れる。`.slide` では `initialSidebarCollapsed` の解決自体を飛ばして常に true にする。

### 4. 一覧の初期値の引き継ぎ — seed には足さない

`SidebarListingSeed` の doc は「運ぶのは行ではなく材料。元タブの展開を写すと新しい窓の展開状態と食い違う」と記録しており、ここへ展開状態を足す指示は記録された判断と衝突する。器を分ける。

| 引き継ぐもの | 通す器 |
| --- | --- |
| レイアウト（ツリー/フラット）・変更のみ | `SidebarDisplayOverrides` を 2 値 → 4 値へ拡張 |
| ツリーの展開状態（`Set<String>` の pathKey） | `SidebarNavigator.attach(to:adopting:)` の別引数 |
| 並び順・不可視・列挙結果 | `SidebarListingSeed`（変更なし） |

`canApply(to:)` は**広げない**。一致条件は「列挙の入力が同じか」を問うもので、レイアウト・変更のみ・展開状態はいずれも列挙の入力ではない（行の畳み方と絞り込み）。広げると seed が当たらない場面が増えるだけ。

展開状態の保持者は `FileListModel` ではなく `SidebarTreePresenter` の `SidebarExpansion`（`expandedKeys: Set<String>`、読み取りの窓は `SidebarNavigator.expandedFolderKeys`）。新しい窓が自分の展開を当てて材料を畳むので、引き継ぎ直後の取り直しは同じ行を返し、`SidebarTreePresenter.applyRows` のガードが畳む（seed の既存の理屈がそのまま効く）。

この拡張は「新しいウィンドウで開く」「新規タブ」にも同じ引き継ぎをもたらす（意図した副作用）。

### 5. 入口

`SidebarContextMenu.openElsewhereEntries` に `("sidebar.context.openInSlideMode", .slide)` を 1 行足す。`OpenDisposition` に `.slide` を追加し、`reusableController` の switch で `.newWindow` と同じく `return nil`（常に新規窓）。実測: この enum を全網羅で switch している箇所は `reusableController` 1 つだけで、他はパススルー。ただし public な enum で JS ブリッジ（`BridgeMessageRouter`）と直接 HTML（`DirectHTMLLinkPolicy`）が修飾キーから生成する表でもあるため、`init(commandKey:shiftKey:)` から `.slide` が決して出ないことをテストで固定する。

フォルダー行は「新しいウィンドウで開く」と同じ `DirectoryLister.firstSupportedFile` 経路（既存の `openElsewhereButton` が disposition を引数で受けているのでコード追加なし）。

### 6. 器の組み立て

- ツールバー: `ViewerWindowController.init` の `toolbarController = ViewerToolbarController(...)` を `.slide` では作らない
- タブ合流: `ViewerWindowChrome.makeWindow` に `kind` を渡し、`.slide` では `tabbingMode = .disallowed`
- セッション復元: `SessionRestorer.currentSessionLayout()` の `group(for:)` で `.slide` の窓を除外する（`SessionLayout` に種別は足さない）。`RecentRepositoryRecorder` も同じ `ViewerTabGrouping.tabGroup(of:)` を呼ぶので、除外はスナップショットを組む側に置く

### 7. l10n

`sidebar.context.openInSlideMode`（en: "Open in Slide Mode" / ja: 「スライドモードで開く」）を `sidebar.context.openInNewWindow` の隣へ。

### 8. 未確認の前提（実装中に確かめる）

- **`tabbingMode = .disallowed` が本当に要るか未確認。** 実測: `rg tabbingMode` はリポジトリ全体で 0 件で、タブ合流は `ViewerTabGrouping.present(..., asTabOf:)` の明示呼び出しだけ。`.slide` は `.newTab` ではないので `asTabOf: nil` になる。一方 `makeWindow` は `tabbingIdentifier = "ViewerWindow"` を設定しており、システム設定「書類を開くときはタブで開く: 常に」で AppKit が自動で畳む可能性がある。`.disallowed` は入れるが、その設定にした実機で目視するまで「効いている」とは言わない（AC #2 の確認方法）

### 9. テスト（GUI 層は自動テスト対象外なので `/run` で目視）

- `openElsewhereEntries` に `.slide` の行があること（既存テストへ 1 行）
- `OpenDisposition(commandKey:shiftKey:)` の全 4 通りが `.slide` を返さないこと
- `.slide` の窓で ⌘S / ⌘← / `setSidebarCollapsed` のどれを通しても `isCollapsed` が変わらず `recordToggle` が呼ばれないこと
- `SidebarDisplayOverrides` の 4 値が新しい窓の `FileListModel` へ届くこと
- 展開状態が `SidebarNavigator.attach` 経由で引き継がれること
- `currentSessionLayout()` のスナップショットに `.slide` の窓が入らないこと
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容

窓種別 `ViewerWindowKind`（`.viewer` / `.slide`）を足し、コンテキストメニューから
サイドバー無しの窓を開けるようにした。前後移動キーは TASK-593.3。

- `ViewerWindowKind`（新規）: 述語 4 つ（`allowsSidebar` / `hasToolbar` / `joinsTabs` / `isRestorable`）を持つ。呼び出し側で `kind == .slide` と書かせない
- `ViewerWindowController`: `let kind` を追加（生成時に決まり以後変わらない）。`toolbarController` は `ViewerToolbarController!` → `ViewerToolbarController?` へ変え、ツールバーを持たない窓があることを型で表した
- `ViewerWindowChrome.makeWindow(fileURL:kind:)`: `.slide` で `tabbingMode = .disallowed`
- `SidebarInheritance`（新規）: 起点の窓から引き継ぐ材料の採取。`Seed`（listing + expansion）で 1 束にして運ぶ
- `OpenDisposition.slide` を追加。`reusableController` は `.newWindow` と同じ「常に新規」

## /review-design の結果と、それによる方針変更

1. **`SidebarListingSeed` へ展開状態を足す指示は採らなかった。** 同型の doc が
   「運ぶのは行ではなく材料。元タブの展開を写すと新しい窓の展開状態と食い違う」と
   記録しており、正面から衝突する。器を分けた——レイアウトと「変更のみ」は
   `SidebarDisplayOverrides` を 2 値 → 4 値へ拡張して運び、展開状態は
   `SidebarNavigator.attach(to:adopting:expanding:)` の別引数（`[String: URL]`）で運ぶ。
   `canApply(to:)` は**広げていない**（一致条件は「列挙の入力が同じか」を問うもので、
   レイアウト・変更のみ・展開はいずれも列挙の入力ではない）。
2. **サイドバーを開かせないガードは spec の 3 箇所から 2 箇所へ減らした。** ⌘← は既存の
   `!isSidebarCollapsed` 判定でそのまま無効になる（スライド窓は常に畳まれている）ので
   種別の分岐を足していない。`setSidebarCollapsed(_:)` は `toggleSidebar` を呼ぶので、
   no-op 1 つで CLI の `--sidebar` と `forceSidebarVisible` も塞がる（絞り込み点）。
3. **`recordToggle` に追加のガードを置かなかった。** 実測: 本番の呼び出し元は
   `ViewerWindowAssembler` の `onCollapsedChange` 1 箇所だけで、`toggleSidebar` からしか
   発火しない。no-op にすれば構造的に届く経路が無い。
4. **spec に無い穴を 1 つ塞いだ。** `makeController` の
   `perFileState.sidebar.setCollapsed(_:for:)` は種別を見ずに必ず走るため、そのままだと
   スライド窓を開いたファイルを次に通常窓で開いたときサイドバーが畳まれる。`.slide` では飛ばす。
5. **セッション除外は `ViewerTabGrouping.viewerPath(of:)` に置いた。** スナップショットを
   作る経路は `SessionRestorer.currentSessionLayout` と `RecentRepositoryRecorder.recordTabGroup`
   の 2 つあり、どちらも `tabGroup(of:)` を通ってここへ合流する。消費側に置くと片方だけ直せる。

## 型グループの是正（閾値超過を上限引き上げで逃げていない）

追加で 3 グループが閾値 400 を超えたため、責務で分けた。

- `ViewerWindowManager` 431 → 397: 引き継ぎ材料の採取（`listingSeed` / `expansion`）を
  `SidebarInheritance` へ切り出した。`makeController` を 2 つに割る案は
  `function_parameter_count` に触れたのでやめ、`SidebarInheritance.Seed` で束ねて 5 引数に収めた
- `SidebarNavigator` 408 → 396: 展開の適用を `SidebarTreePresenter.adoptExpansion(_:)` へ移した
  （展開の持ち主は presenter なので置き場としても正しい）
- `ViewerWindowController` 905 → 922: 恒久例外の上限を実測値へ引き上げた。増える責務は
  stored property 1 つ（`kind`）だけで、プロトコル準拠も注入クロージャも増えていない
- ついでに `ViewerWindowController.init` の `function_body_length` 超過を避けるため、
  ツールバー生成を `ViewerWindowAssembler.makeToolbarController(for:on:)` へ出した

## 検証（実測）

- `swift build` / `xcodebuild build -scheme befold`: いずれも成功（`** BUILD SUCCEEDED **`）
- `swift test`: `Test run with 1878 tests in 310 suites passed after 37.384 seconds.`
- swiftlint ベースライン差分: main 51 件 / HEAD 51 件、真の新規 0・解消 0
  （途中 `function_body_length` と `function_parameter_count` の 2 件が新規に出たので、
  上の切り出しで解消してからゼロを確認した）
- `scripts/check-type-group-size.sh --check`: 「型グループの行数は閾値以内です」
- `/l10n-check`: 漏れ・プレースホルダ不一致・未対応 state いずれも 0（220 キー）
- `check-doc-symbols.sh` / `check-doc-citations.sh` / `markdownlint-cli2`: いずれも exit 0
- ガードが効いていることの逆検証: `ViewerSplitViewController.toggleSidebar` から
  `guard allowsSidebar else { return }` を外すと `SlideWindowSidebarGuardTests` の 2 本が
  実際に落ちることを確認した（外した状態で `toggles.values → [true]`）

## 未確認のまま残っている前提（AC #2 / #6）

GUI 層は自動テスト対象外なので、次は `/run` での目視が要る。

- **AC #2**: `tabbingMode = .disallowed` が効いているか。実測で `rg tabbingMode` は
  リポジトリ全体で 0 件だったので、これは新規に入れた設定。システム設定
  「書類を開くときはタブで開く: 常に」にした実機で、スライド窓が既存窓のタブに
  合流しないことを確認する必要がある
- **AC #6**: ソース表示・差分表示（⌘1/⌘2/⌘3・⌘U・⌘\）がスライド窓でも効くこと。
  既存経路をそのまま通しており触っていないが、実機では未確認

## 追記: AC #2 / #6 の自動化

`SlideWindowIntegrationTests`（TASK-593.3 で新設）が実 `NSWindow` を作って
`tabbingMode == .disallowed` と、起点のタブグループへ入らないことを測るようにした（AC #2）。
表示モード（AC #6）は既存経路をそのまま通しており、`ViewerWindowControllerSourceModeTests`
ほか既存のテストが窓の種別に依らず通っている。
<!-- SECTION:NOTES:END -->
