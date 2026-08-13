---
id: TASK-453
title: ViewerWindowController（型グループ 855 行）を責務ごとにさらに切り出す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-11 14:24'
updated_date: '2026-08-12 01:26'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 100750
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-441 で 1255 → 852 行まで縮めた ViewerWindowController の型グループが、TASK-449（外部 URL の届け先を ReferenceActions へ寄せる修正）で 855 行へ戻った（scripts/check-type-group-size.sh の実測。ベースラインは scripts/type-group-baseline.txt:14 の 852 行）。集計対象の中で最大であり、TASK-428 のラチェットを最終的に撤去して単純な閾値強制へ畳む（TASK-428.5）ためには返済が要る。

型グループは 'ViewerWindowController.swift + 同ディレクトリの ViewerWindowController+*.swift' の合算なので、extension へ割っても減らない。責務を別の型へ切り出すこと。前例は TASK-441（ReferenceResolutionCoordinator / ReferenceMenuPresenter の切り出し）と TASK-442（SidebarNavigator から git status 関心を独立型へ）。

なお、直近の 3 行増（externalOpener の doc と referenceActions.openExternal の配線）は TASK-449 の修正に必要なもので、巻き戻す対象ではない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 候補となる責務の切り出し先を洗い出し、選んだ分割方針とその理由を Implementation Plan に書いている（extension への再配置ではなく別型への切り出しであること）
- [x] #2 ViewerWindowController の型グループ合算が 852 行（TASK-441 到達点）以下になり、scripts/type-group-baseline.txt を更新している
- [x] #3 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
- [x] #4 xcodegen generate 済みで xcodebuild build が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 切り出し候補の洗い出し: 型グループ 855 行の内訳は本体 337 + 拡張 7 本(Capabilities 38 / FileNavigation 122 / MenuActions 161 / References 60 / Renderer 54 / SidebarHost 43 / WindowDelegate 40)。本体は依存保持・init・協働オブジェクト宛ファサードで、Renderer / SidebarHost / WindowDelegate / References は既に薄い委譲。残る「判断」は MenuActions の validateMenuItem / validateDisplayModeItem(52 行)の対応表と、+Capabilities の canSelect(mode) の導出だけ。よってこの 2 つを別型へ移す。
2. canSelect の導出を ViewerCapabilities.canSelect(_:) へ移す(ADR 0002 の「条件は ViewerCapabilities の 1 箇所」に沿う。現在は capabilities の 3 フラグを窓側で switch し直している)。ViewerToolbarHost 要求の窓側 canSelect は 1 行委譲に縮む。
3. メニュー有効判定の対応表を新型 ViewerMenuValidator(App/ViewerMenuValidator.swift)へ切り出す。ウィンドウを知らない純粋型にするため、参照する状態は protocol ViewerMenuValidationSource で受ける(capabilities / isSourceMode / showLineNumbers / isBookmarked / canGoBack / canGoForward / effectiveDisplayMode / isDiffLayoutSideBySide / canSelect)。ViewerWindowController の適合宣言は新ファイル側に置く(プロトコルとその配線を 1 箇所にまとめる)。@objc アクション本体は NSResponder チェーンの都合でコントローラに残す。
4. validateMenuItem は ViewerMenuValidator.validate(menuItem, source: self) への委譲だけにする。
5. ViewerMenuValidator の単体テスト(スタブ source)を追加。従来はウィンドウ生成なしに検証できなかった。
6. scripts/check-type-group-size.sh で 852 行以下を確認しベースライン更新、swift test / swiftlint 差分 / xcodegen generate + xcodebuild build。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-449 のマージ時にベースラインを 852 → 855 行へ引き上げた（外部 URL の届け先を weak 捕捉クロージャへ寄せる配線と、externalOpener を internal にした理由の doc）。このタスクの到達目標は引き上げ後の 855 ではなく、TASK-441 の到達点である 852 行以下。

実装: (1) canSelect(_:) の導出を ViewerWindowController+Capabilities から ViewerCapabilities へ移した(ADR 0002 の「条件は 1 箇所」に合わせた。窓側は ViewerToolbarHost の要求を満たす 1 行委譲)。(2) メニュー有効判定の対応表(validateMenuItem / validateDisplayModeItem, 52 行)を新型 ViewerMenuValidator へ切り出した。参照する状態は protocol ViewerMenuValidationSource で受けるため、ウィンドウを生成せずに検証できる。@objc アクション本体は NSResponder チェーンの都合でコントローラに残し、validateMenuItem は 3 行の受け口になった。ViewerWindowController の適合宣言と別名メンバー(showLineNumbers / canGoBack / canGoForward)はプロトコルと同じ ViewerMenuValidator.swift に置いた。

実測: 型グループ 855 → 802 行(scripts/check-type-group-size.sh)。--update-baseline でベースライン更新済み、--check は「ベースライン以内です」。swift test は 214 suites / 1441 tests 全通過(新規 ViewerMenuValidatorTests 8 ケース込み)。swiftlint は origin/main を git archive で別ディレクトリへ展開して比較し、真の新規・解消ともに 0 件。xcodegen generate 済みで xcodebuild build -scheme befold は BUILD SUCCEEDED。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowController の型グループから、メニュー有効判定の対応表を ViewerMenuValidator(+ ViewerMenuValidationSource)へ、モード選択可否の導出を ViewerCapabilities.canSelect(_:) へ切り出し、855 → 802 行に縮めた(TASK-441 到達点の 852 以下)。判定がウィンドウから独立したため、従来ウィンドウ生成なしには検証できなかったメニュー有効判定・項目名・チェック状態をスタブ 1 個で押さえる ViewerMenuValidatorTests を追加。検証は swift test 1441 件全通過 / swiftlint の main 比 新規 0 件 / xcodebuild BUILD SUCCEEDED / check-type-group-size.sh --check 合格。
<!-- SECTION:FINAL_SUMMARY:END -->
