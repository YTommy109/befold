---
id: TASK-429
title: AppDelegate（495 行）を責務ごとに分割する
status: To Do
assignee: []
created_date: '2026-08-10 12:35'
updated_date: '2026-08-11 05:25'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 100400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/App/AppDelegate.swift` は 495 行（`wc -l` 実測、2026-08-10 時点）で `BefoldApp/.swiftlint.yml:13-15` の `file_length` warning 400 を超えている。TASK-428 のラチェットを最終的に撤去して単純な閾値強制へ畳むには、この負債の返済が必要。

分割の作法はプロジェクト既定の `Type+Feature.swift` extension、または独立型への切り出し（前例: `SidebarNavigator` / `ViewerToolbarController`）。ただし TASK-411 の Description が記録しているとおり、行数上限の回避だけを目的とした extension 分割は責務の分離にならない。凝集単位で切ること。

着手時に確認すべき制約: `AppDelegate` は `NSApplicationDelegate` 準拠であり、プロトコル準拠メソッドはレスポンダチェーン／フレームワークから呼ばれるため静的な呼び出し元を持たない（`.claude/CLAUDE.md` の「知識グラフの Swift での限界」節）。移動可否はグラフではなく実コードで判断する。また Sparkle 2 の `SPUStandardUpdaterController` を保持している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AppDelegate.swift が file_length warning の 400 行以下になる
- [ ] #2 分割が行数回避ではなく責務単位になっている（各分割先が何を担うかを 1 行で言える）
- [ ] #3 main との swiftlint 差分に真の新規が無い（/swiftlint-baseline の手順で確認）
- [ ] #4 swift test が既存どおり通る
- [ ] #5 新規ファイルを追加した場合 xcodegen generate 済みで xcodebuild build が通る
<!-- AC:END -->
