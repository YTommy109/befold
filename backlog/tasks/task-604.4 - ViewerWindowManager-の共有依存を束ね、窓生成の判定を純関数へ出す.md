---
id: TASK-604.4
title: ViewerWindowManager の共有依存を束ね、窓生成の判定を純関数へ出す
status: Done
assignee: []
created_date: '2026-09-09 00:02'
updated_date: '2026-09-09 00:54'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-604
priority: medium
ordinal: 880000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/App/ViewerWindowManager` グループは 389 行（本体 203 + `+OpenViewer` 176 + `+SessionSync` 10）。TASK-459 で 610 → 368 へ返済済みだが、その後 +21 行（共有依存の宣言と doc の追加、窓種別対応）で戻っている。

## 返済先（約 −90 行、389 → 約 300）

**(a) 共有依存の束 → `ViewerWindowDependencies`（struct、−65）**
stored property 20 個・init 引数 21 個のうち 10 個は「受け取って `ViewerWindowController.init` へ素通しするだけ」。`ViewerWindowManager.swift:45-64` の `displayDefaults` / `diffDisplayPreference` / `diffLoader` / `findOptionsPreference` / `headingJumpLevelDefaults` / `codeFontPreference` / `csvNumberFormatPreference` / `perFileState` / `windowFrame` / `bookmarkStore`。

**同じ束を `ViewerWindowController.init` も受けるので、恒久例外グループ 931 行のほうも同時に縮む。**

**(b) 初期サイドバー状態の解決 → 純関数（−22）**
`+OpenViewer.swift:121-145`。`kind.allowsSidebar > options.showSidebar > forceSidebarVisible > per-file の記憶` の優先順位判定。

**(c) 既存窓の再利用規則 → `ViewerWindowReusePolicy`（−25）**
`+OpenViewer.swift:88-104` の `reusableController`。既存の `ViewerDisplayOptionsApplier`（43 行）と同じ粒度。

## 注意（TASK-604 の判定で訂正済み）

注入クロージャは **3 本**（`presentFileNotFound` / `makeStore` / `makeContentView`）で上限ちょうど。**規約違反ではない**ので、これは違反の是正ではなく先回りの返済。

## 制約

- `befoldTests/SharedDependencyDefaultsTests.swift:18-21` が `ViewerWindowManager.swift` / `ViewerWindowController.swift` の宣言ソースを正規表現で読む（TASK-558）。`sources` へ新ファイルを足すのが必須
- `befoldTests/MockedViewerWindowManager.swift:65-` が隔離 UserDefaults でストアを個別に作るため、`AppStores` をそのまま渡す形にはできない。**既に作られたインスタンスを受け取る struct** にすること
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ViewerWindowManager グループが 320 行以下になっている
- [x] #2 SharedDependencyDefaultsTests の sources に新ファイルが含まれ、既定値の再発検知が片側だけにならない
- [x] #3 MockedViewerWindowManager が隔離 UserDefaults のまま動く
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー（/review-design、2026-09-09）を反映した方針

### (a) 共有依存の束 → ViewerWindowDependencies（新規 struct）

`befold/App/ViewerWindowDependencies.swift` に、窓の生成経路を素通しする共有物を
束ねた struct を置く。収めるのは **8 個**:
displayDefaults / diffDisplayPreference / findOptionsPreference /
headingJumpLevelDefaults / codeFontPreference / csvNumberFormatPreference /
perFileState / bookmarkStore。

**windowFrame は入れない。** ViewerWindowController は受け取っておらず、束へ入れると
窓側から見えるようになる（TASK-583 で「解決結果を書き戻さない」と決めた相手なので
見える範囲を広げない）。ViewerWindowManager の stored property として残す。

**diffLoader も入れない（レビューで方針変更）。** 両側で型が違う——
`ViewerWindowManager.diffLoader` は非 Optional（「この型が唯一の持ち主」と doc が宣言）、
`ViewerWindowController.init` は `GitDiffLoader? = nil`（nil = 差分を取りに行かない）で、
`ViewerWindowControllerFixture.diffLoader` も `GitDiffLoader? = nil`。1 フィールドへ畳むと
どちらかの性質を捨てることになる（非 Optional にすればテストの「差分に無関心」が
表現できず、Optional にすれば VWM 側の唯一の持ち主保証が消える）。両側の引数として残す。

**struct の init に既定値を一切付けない。** 付けると構築点のどこかでの渡し忘れが
コンパイルエラーにならず、TASK-319 と同型の穴が「束の中」へ移動するだけになる。

### (b)(c) 窓を開く経路の判定 → ViewerWindowOpenPolicy（新規 enum・1 ファイル）

当初案は純関数（初期サイドバー）と ViewerWindowReusePolicy（再利用規則）で
別々の受け皿を立てるつもりだったが、どちらも「窓を開くときの純粋な判定」で
入力も同種なので 1 つの型に置く（型を 3 つ立てない）。

- `reusableController(from candidates:disposition:relativeTo:)`
  — `controllers` 辞書は引かせず、候補配列を引数で受ける
- `initialSidebarCollapsed(kind:showSidebar:forceSidebarVisible:remembered:)`
  — `remembered` は `@autoclosure () -> Bool` で受け、`!kind.allowsSidebar` のときに
    per-file 記憶を読まない現在の短絡を保つ（`SidebarStateStore.initialCollapsed` は
    読み取りのみで副作用は無いが、短絡を落とす理由も無い）

記憶への書き戻し（`setCollapsed`）は副作用なので呼び出し側（`makeController`）に残す。

### 検査の追随（AC #2 の核心）

`SharedDependencyDefaultsTests` は `name: Type = Type(` の形を探すため、共有物の引数が
束へ移ると **VWM / VWC のどちらを読んでも該当引数が 1 つも無くなり、緑のまま無検査に
なる**（0 件は成功条件なので、対象が消えたことと区別できない）。sources へ
`befold/App/ViewerWindowDependencies.swift` を足すだけでは、この「静かな無効化」は塞げない。

そこで**存在確認のテストを 1 本足す**: `ViewerWindowDependencies.swift` が期待する
8 つの共有物名をプロパティとして宣言していることを見る。名前が消える・改名される・
束が空になると落ちるので、検査対象が消えたことに気づける。

### 確認

swift test / check-type-group-size.sh / swiftformat / swiftlint ベースライン差分。
MockedViewerWindowManager が隔離 UserDefaults のまま動くこと（AC #3）。

### 実測（着手前）

- ViewerWindowManager グループ 389 行 → (a) で約 −45（stored 8 + init 引数 8 +
  代入 8 + 共有物の doc）、(b)(c) で約 −47。見積り 約 297 行（AC #1 は 320 以下）
- **(a) だけでは 320 に届かない**（389 − 45 ≒ 344）ので (b)(c) は任意ではなく必須
- ViewerWindowController グループ 931 行（恒久例外の上限に張り付き）→ 引数 8 本ぶん
  約 −8。上限は動かさない
- 構築点はコンパイルエラーで全数検出できる: ViewerWindowManager 5 箇所
  （ViewerWindowManagerFactory / MockedViewerWindowManager /
  ViewerWindowManagerRecentRepositoriesTests / ViewerWindowManagerIntegrationTests /
  ViewerWindowManagerDisplayOverridesIntegrationTests）、
  ViewerWindowController 2 箇所（+OpenViewer / ViewerWindowControllerFixture）

### チェックリストで該当しなかった項目

1 判定の真実の源 / 2 既存の不変条件 / 4 新しい状態の表示 / 8 非同期の世代管理:
新しい述語も縮退も非同期も増やさず、判定の中身は現行のまま位置だけを移す。
5 ライフサイクル: struct は参照を束ねる値型で、生成の回数も順序も変わらない。
6 高頻度経路: 触るのは窓の生成経路のみで、描画・監視コールバックには乗らない。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- `befold/App/ViewerWindowDependencies.swift`（新規）: 共有物 8 個の束。init に既定値なし。
  windowFrame / diffLoader / gitFileIndex / gitStatusStore は計画どおり入れていない。
- `befold/App/ViewerWindowOpenPolicy.swift`（新規）: `reusableController(from:disposition:relativeTo:)`
  と `initialSidebarCollapsed(kind:showSidebar:forceSidebarVisible:remembered:)`（remembered は
  @autoclosure で短絡を保つ）。`setCollapsed` の書き戻しは makeController に残した。
- `ViewerWindowController` 側は束を受け取って init 内で既存の stored property へ展開する形にした。
  拡張 7 本の参照を書き換えずに済み、差分が最小になる（束の再エクスポートはしない）。

## 実測

- 行数: ViewerWindowManager グループ 389 → 319（175 + 134 + 10）。AC #1（320 以下）を満たす。
  ViewerWindowController グループは 970 → 959。
- `swift test`: 1942 tests / 320 suites すべて成功。
- swiftlint: main とのベースライン差分ゼロ（両側 50 件、行番号正規化後 diff 空）。
- swiftformat: 変更なし。

## 検査の追随（AC #2）

`SharedDependencyDefaultsTests.sources` へ `ViewerWindowDependencies.swift` を追加した上で、
`dependenciesBundleDeclaresSharedMembers` を新設した。既存 2 テストは共有物が束へ移ったことで
「対象 0 件でも緑」になるため、束が 8 つのプロパティを宣言していること自体を見る。

## テスト側（AC #3）

`makeViewerWindowDependencies(defaults:...)` を `ViewerWindowControllerTestSupport.swift` に置き、
隔離 UserDefaults から束を組む。`MockedViewerWindowManager` / `ViewerWindowControllerFixture` は
差し替えたいフィールド（displayDefaults / diffDisplayPreference / perFileState / bookmarkStore）
だけを渡す。本体側 init の「既定値なし」は変えていない。
<!-- SECTION:NOTES:END -->
