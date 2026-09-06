---
id: TASK-593.1
title: 旧サイドバー内スライドモードを撤去する
status: Done
assignee: []
created_date: '2026-09-06 09:25'
updated_date: '2026-09-06 09:42'
labels:
  - sidebar
  - slide-mode
dependencies: []
documentation:
  - docs/superpowers/specs/2026-09-06-slide-window-design.md
parent_task_id: TASK-593
priority: medium
type: chore
ordinal: 859000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
新しいスライド窓を足す前に、TASK-585 / 587 で入れたサイドバー内スライドモードを撤去する。先に消すのは、2 つの「スライドモード」が同時に存在する期間を作らないため（l10n キー `menu.view.slideMode` の意味が変わる、View メニューとコンテキストメニューに別物が並ぶ）。

撤去対象は spec の「旧モードの撤去」節に列挙してある: `SlideModeCoordinator`、`SidebarSlideMetrics`、`SidebarTransientState.isSlideMode` / `setSlideMode(_:)`、`ViewerSplitViewController.setSlideMode(_:)` と `thicknessBeforeSlideMode` / `setAutosaveEnabled(_:)`、`SidebarCollapsible.setSlideMode`、`FileListView` の `.redacted(reason:)`、`SidebarHeaderView` の解除アイコン分岐、`MainMenuBuilder+ViewMenu.swift` の項目、`ViewerWindowController.toggleSlideMode(_:)` / `isSlideMode`、`ViewerMenuValidator` の分岐、`ViewerWindowAssembler.makeSidebarDidHide` のスライド解除、`SidebarDisplayRequest.slideMode`、xcstrings の `menu.view.slideMode` / `sidebar.slideMode.exit`、native-app-design.md の該当行。

`SidebarDisplayRequest` が `.display` だけになるなら列挙ごと畳み、`fileListDidRequestDisplayChange` は `SidebarDisplayChange` を直接受ける形にしてよい（TASK-586 で `.slideMode` を `SidebarDisplayChange` に混ぜなかった理由は幅の面倒を見せないためで、撤去後は理由ごと消える）。

TASK-588 / 589 は対象が消えるので、このタスクの完了時に「見送り（旧モード撤去により対象消滅）」の Final Summary を付けて Done にする。TASK-590 / 591 / 592 は `.slideMode` を前提にした記述を持つので Description / AC を実態に合わせて書き換える。

TASK-585 の Implementation Notes にある「幅 480 への上限拡大」はスライドモードと独立した変更なので残す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 上記の旧シンボルが `rg` で 0 件で、swift build / swift test / xcodebuild が通る
- [x] #2 View メニューにスライドモードの項目が無く、サイドバーヘッダーに解除アイコンの分岐が無い
- [x] #3 `/l10n-check` が通り、`menu.view.slideMode` と `sidebar.slideMode.exit` が xcstrings から消えている
- [x] #4 サイドバー幅の上限 480 と `ViewerSplitViewController` の autosave の挙動は変わっていない（既存テストが通る）
- [x] #5 TASK-588 / 589 が見送りの要約付きで Done になり、TASK-590 / 591 / 592 の Description と AC から `.slideMode` の前提が消えている
- [x] #6 native-app-design.md の SidebarSlideMetrics / SlideModeCoordinator / SidebarTransientState の記述が撤去後の実態に合っている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容

撤去したシンボル（`rg` で 0 件を確認）:
- ファイルごと削除: `SlideModeCoordinator.swift` / `SidebarSlideMetrics.swift` と対応するテスト 2 本
- `SidebarTransientState`: `isSlideMode` / `setSlideMode(_:)`（`closeFilter()` は残す）
- `ViewerSplitViewController`: `setSlideMode(_:)`・`thicknessBeforeSlideMode`・`setAutosaveEnabled(_:)`。`SidebarCollapsible` からも `setSlideMode` を削除
- `ViewerWindowController+MenuActions`: `toggleSlideMode(_:)` / `isSlideMode`
- `ViewerMenuValidator`: `ViewerMenuValidationSource.isSlideMode` と `toggleSlideMode` の分岐
- `MainMenuBuilder+ViewMenu`: View メニューの項目
- `SidebarHeaderView`: `slideModeIndicator` とヘッダーの分岐
- `FileListView`: `.redacted(reason:)`
- `ViewerWindowAssembler.makeSidebarDidHide`: スライド解除を落とし、保留フォーカスの取り消しだけにした
- xcstrings: `menu.view.slideMode` / `sidebar.slideMode.exit`（219 キーへ）

## 単純化（着手前の検討結果）

Description が許した `SidebarDisplayRequest` の畳み込みを実施した。`.slideMode` が消えて `case display(SidebarDisplayChange)` の 1 ケースだけになるため、列挙ごと撤去し `fileListDidRequestDisplayChange(_ change: SidebarDisplayChange)` が `SidebarDisplayChange` を直接受ける形にした。連動して `SidebarHeaderView.displayRequest(for:)` → `displayChange(for:)`、`SidebarDisplayRequestRoutingTests` → `SidebarDisplayChangeRoutingTests`（5 種 → 4 種）へ改名。`ViewerWindowController+FileList` の switch も 1 行の委譲になった。

## `setAutosaveEnabled` の扱い

スライドモード中だけ autosave を止める必要が消えたので private ヘルパーを削除し、`viewWillAppear` の 1 箇所で `splitView.autosaveName = Self.autosaveName` を直接代入する形に戻した。autosaveName を触る場所は引き続き 1 箇所。

## type-group-exceptions

`ViewerWindowController` の上限は TASK-585 で `toggleSlideMode` を足した際に 900 → 920 へ上げたもの。撤去後の実測が 905 行なので上限を 905 へ戻した（実測値へ張り付ける運用にした旨をコメントに明記）。

## 検証（実測）

- `swift build`: Build complete
- `swift test`: `Test run with 1865 tests in 306 suites passed after 37.371 seconds.`
- `xcodebuild build -scheme befold`: `** BUILD SUCCEEDED **`
- swiftlint ベースライン差分（`/swiftlint-baseline`）: main 51 件 / HEAD 51 件、真の新規 0・解消 0
- `/l10n-check`: 翻訳漏れ・プレースホルダ不一致・未対応 state いずれも 0（219 キー）
- `scripts/check-type-group-size.sh` / `check-doc-symbols.sh` / `check-doc-citations.sh` / `markdownlint-cli2`: いずれも exit 0

## 残置

TASK-585 の「幅の上限 480」はスライドモードと独立なので残した（`minimumSidebarWidth` の doc から「スライドモードはこれを一時的に下回る」の一文だけ削除）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバー内スライドモード（TASK-585 / 587）を撤去した。真値・幅の適用・ヘッダーの解除アイコン・行のマスク・View メニュー項目・l10n キーをすべて消し、`SidebarDisplayRequest` の 1 段包みも `SidebarDisplayChange` へ畳んだ。TASK-588 / 589 は対象消滅により見送りで Done、TASK-590 / 591 / 592 は前提を実態へ書き換えた。
<!-- SECTION:FINAL_SUMMARY:END -->
