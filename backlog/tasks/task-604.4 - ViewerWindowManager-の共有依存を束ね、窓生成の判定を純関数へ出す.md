---
id: TASK-604.4
title: ViewerWindowManager の共有依存を束ね、窓生成の判定を純関数へ出す
status: To Do
assignee: []
created_date: '2026-09-09 00:02'
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
- [ ] #1 ViewerWindowManager グループが 320 行以下になっている
- [ ] #2 SharedDependencyDefaultsTests の sources に新ファイルが含まれ、既定値の再発検知が片側だけにならない
- [ ] #3 MockedViewerWindowManager が隔離 UserDefaults のまま動く
<!-- AC:END -->
