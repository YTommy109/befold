---
id: TASK-419
title: MainMenuBuilder のフィーチャーゲート直接参照を引数注入へ切り出す
status: To Do
assignee: []
created_date: '2026-08-10 07:28'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 507500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
.claude/CLAUDE.md は「ゲート値を引数で受ける純粋関数へ切り出し、ON/OFF 両方向をユニットテストで押さえる」を定め、模範として MainMenuBuilder.addDisplayModeItems(to:isSourceDiffEnabled:) を名指ししている。また OFF 側はローカルの Release ビルドでは確認できない（署名の Team ID 不一致で起動しない）ことも明記している。

しかし makeViewMenuItem（MainMenuBuilder.swift:222）は FeatureGate.isSidebarGitStatusEnabled をその場で読んで分岐しており、stable（OFF）での View メニューの形が何によっても検証されていない。addDisplayModeItems はその 60 行下で引数として受けている。

同じゲートを同じくその場で読んでいる箇所: ViewerWindowController.makeChangedFilesOnlyToggle（:391）、makeSidebarGitStatusLoader（:16）。

.swiftlint.yml の custom rule feature_gate_direct_reference と excluded の allowlist、および FeatureGateEnumerationTests との整合も同時に確認する（allowlist に載せてよいのは配線点だけで、その場分岐は理由にならない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 makeViewMenuItem がゲート値を引数で受け取り、ON/OFF 両方をユニットテストで検証できる
- [ ] #2 makeChangedFilesOnlyToggle / makeSidebarGitStatusLoader も同じ形へ揃える
- [ ] #3 stable（OFF）で「変更ファイルのみ表示」項目が View メニューに出ないことをテストで担保する
- [ ] #4 .swiftlint.yml の excluded と FeatureGateEnumerationTests が実態と一致する
<!-- AC:END -->
