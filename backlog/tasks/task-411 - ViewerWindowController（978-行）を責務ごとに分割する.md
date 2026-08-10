---
id: TASK-411
title: ViewerWindowController（978 行）を責務ごとに分割する
status: To Do
assignee: []
created_date: '2026-08-10 07:25'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 500000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/befold/App/ViewerWindowController.swift は 978 行（wc -l 実測）で、BefoldApp/.swiftlint.yml の file_length error（1000）まで残り 22 行しかない。SwiftLintPlugins はビルドステップで走るため、この上限に達した時点でビルドが error severity で落ちる。

1 つの型が次をすべて所有している: ウィンドウクロム、スプリットビュー構築、サイドバー/ツールバーのホスティング、WebView コマンド配線、ファイル単位の永続化、表示モード遷移、スクロール/ズームの記録、参照解決、ペーストボード、メニュー検証。加えて 5 つのプロトコル準拠（SidebarNavigatorHost / ViewerRendererDelegate / ReferenceResolutionHost / ViewerToolbarHost / NSWindowDelegate）を兼ねる。すでに +Capabilities / +Diff / +WindowHelpers の 3 拡張が存在するが、これは同じ行数上限を回避するために切られたものであり責務の分離にはなっていない。

init も 199-333 行（非コメント 86 行）で function_body_length の warning 50 を超過しており、error 100 まで 14 行。ストア構築・サイドバーナビゲータ・NSWindow とクロム・ツールバーコントローラ・WebViewCommandController・スプリットビュー・フレーム復元・スワイプモニタ・ストアコールバック配線・表示モード復元・提示開始という 11 の工程が順序制約つきで並んでおり、順序制約はコメント 8 個で説明されている。

ViewerToolbarController / SidebarNavigator が既に独立オブジェクトになっている前例があるので、残りのプロトコル準拠も同じ形へ寄せられる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ViewerWindowController.swift が file_length warning の 400 行以下になる
- [ ] #2 init のボディが function_body_length warning の 50 行以下になる
- [ ] #3 +Capabilities / +Diff / +WindowHelpers の 3 拡張が、行数回避ではなく責務単位の分割として再編される（または独立型へ移る）
- [ ] #4 main との swiftlint ベースライン差分がゼロである（/swiftlint-baseline の手順で確認）
- [ ] #5 swift test が既存どおり通る
<!-- AC:END -->
