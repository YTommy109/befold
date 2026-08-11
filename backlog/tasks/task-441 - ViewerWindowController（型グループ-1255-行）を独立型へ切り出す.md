---
id: TASK-441
title: ViewerWindowController（型グループ 1255 行）を独立型へ切り出す
status: To Do
assignee: []
created_date: '2026-08-11 05:05'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 109200
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
- [ ] #1 型グループの合算行数が 400 行以下になる（scripts/check-type-group-size.sh で確認できる）
- [ ] #2 ベースライン scripts/type-group-baseline.txt から ViewerWindowController のエントリが消える
- [ ] #3 extension の本数が減っており、切り出し先が独立型になっている（Type+Feature.swift の追加で行数を移しただけになっていない）
- [ ] #4 ViewerWindowController が兼ねるプロトコル準拠の数が減っている
- [ ] #5 新規ファイル追加後に xcodegen generate を実行し xcodebuild でも通る
- [ ] #6 main との swiftlint 差分に真の新規が無く、swift test が既存どおり通る
<!-- AC:END -->
