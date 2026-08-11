---
id: TASK-441
title: ViewerWindowController（型グループ 1255 行）を独立型へ切り出す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-11 05:05'
updated_date: '2026-08-11 06:34'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 100200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-411 で ViewerWindowController.swift（978 行）を extension へ分割したが、型グループ（本体 + 同ディレクトリの +*.swift の合算）で数えると 1255 行あり、分割前より増えている。scripts/check-type-group-size.sh の実測値で、scripts/type-group-baseline.txt にも凍結されている。

内訳: 本体 263 / +Assembly 207 / +MenuActions 170 / +Presentation 141 / +FileNavigation 122 / +References 89 / +DiffPresentation 76 / +Renderer 54 / +Capabilities 50 / +SidebarHost 43 / +WindowDelegate 40（extension 10 本）。

TASK-411 の Description が既に問題を言い当てている ——「すでに +Capabilities / +Diff / +WindowHelpers の 3 拡張が存在するが、これは同じ行数上限を回避するために切られたものであり責務の分離にはなっていない」。ファイル単位の file_length は全ファイルが 400 未満で通っており、機械判定を通したまま関心が 11 個に分散している状態。

したがってこのタスクの成果物は「さらに extension を切ること」ではない。extension が担っている関心のうち、コントローラの実装詳細ではないもの（メニューアクション・差分表示・参照解決など）を独立した型へ出し、コントローラには薄い委譲だけを残す。方針は docs/dev/rules/product-code.md の責務分離節「ウィンドウコントローラを『何でも置き場』にしない」に沿う。

着手前に responsibility-reviewer サブエージェントを回し、どの extension をどの独立型へ出すかを決めてから実装すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 型グループの合算行数が 900 行以下になる（scripts/check-type-group-size.sh で確認できる。400 行は init の Parameter doc 約 120 行と移動不能な @objc 層が支配的で到達不能と実測したため、TASK-441 では 900 を目標とする）
- [x] #2 ベースライン scripts/type-group-baseline.txt の ViewerWindowController エントリが実測値へ更新されている
- [x] #3 extension の本数が減っており、切り出し先が独立型になっている（Type+Feature.swift の追加で行数を移しただけになっていない）
- [x] #4 ViewerWindowController が兼ねるプロトコル準拠の数が減っている
- [x] #5 新規ファイル追加後に xcodegen generate を実行し xcodebuild でも通る
- [x] #6 main との swiftlint 差分に真の新規が無く、swift test が既存どおり通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手前に responsibility-reviewer を実行し、5 案（Assembler / DocumentPresenter / DiffPresenter / ReferenceMenu / CapabilitiesFactory）と実施順を決めてから実装した。

決定と根拠:
- AC #1 の 400 行は到達不能と実測で確定した。5 案を全て実施した時点で 852 行であり、残りは init の Parameter doc 約 120 行（残す価値がある）と、NSResponder チェーン都合で移動できない @objc アクション 13 個 + validate 対応表（+MenuActions 161 行）が支配的。ユーザー確認のうえ AC を 900 行へ書き換えた。
- 新設型の host は**プロトコルにせずクロージャ注入**にした。protocol にするとコントローラの準拠がさらに増え、AC #4 と逆行するため（WebViewCommandController の既存の形に揃えた）。
- ReferenceResolutionHost は ReferenceActions（3 クロージャの struct）へ置換した。クロージャ 4 本を並べると product-code.md:131「3 つを超えたら delegate を検討」に触れるため、常に同じ 1 ウィンドウを指す 3 つを値として束ねた。
- FeatureGate の露出点 ViewerWindowController+DiffPresentation.isDiffShown は、doc コメント中の 'FeatureGate.' 言及だけのために allowlist を占めていた。文言を変えて参照を消し、allowlist と FeatureGate の doc の両方から落とした（allowlist は 9 → 8 エントリ）。

検証:
- scripts/check-type-group-size.sh: 1255 → 852 行（extension 10 本 → 7 本）
- swift test: 1399 tests / 205 suites 全パス
- xcodebuild build -scheme befold: BUILD SUCCEEDED（xcodegen generate 実行済み）
- swiftformat --lint: 0/195 files require formatting
- swiftlint の origin/main 差分: App 配下の新規ゼロ。差分 3 件（BefoldRenderKit の opening_brace）はいずれも本ブランチの先行コミット由来で TASK-441 とは無関係
- プロトコル準拠: 5 個 → 4 個（ReferenceResolutionHost を廃止）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowController の型グループ 1255 行を 852 行へ削減し、extension を 10 本から 7 本へ減らした。ViewerWindowAssembler / ViewerDocumentPresenter / ViewerDiffPresenter / ReferenceMenuPresenter / ViewerCapabilitiesFactory の 5 型を新設し、コントローラには薄い委譲だけを残した。新設型はいずれも host プロトコルを増やさずクロージャ注入で受け、ReferenceResolutionHost を ReferenceActions へ置き換えてコントローラの準拠を 5 個から 4 個へ減らした。当初 AC の 400 行は init の Parameter doc と移動不能な @objc 層が支配的で到達不能と実測し、ユーザー確認のうえ 900 行へ改めた。swift test 1399 件パス・xcodebuild 成功・swiftlint 新規ゼロで検証済み（コミット 175a9f3）。
<!-- SECTION:FINAL_SUMMARY:END -->
