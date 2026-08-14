---
id: TASK-419
title: MainMenuBuilder のフィーチャーゲート直接参照を引数注入へ切り出す
status: Done
assignee: []
created_date: '2026-08-10 07:28'
updated_date: '2026-08-13 07:53'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 108000
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
- [x] #1 makeViewMenuItem がゲート値を引数で受け取り、ON/OFF 両方をユニットテストで検証できる
- [x] #2 makeChangedFilesOnlyToggle / makeSidebarGitStatusLoader も同じ形へ揃える
- [x] #3 stable（OFF）で「変更ファイルのみ表示」項目が View メニューに出ないことをテストで担保する
- [x] #4 .swiftlint.yml の excluded と FeatureGateEnumerationTests が実態と一致する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
起票時に指されていた行は移動済み: makeViewMenuItem は MainMenuBuilder+ViewMenu.swift、makeChangedFilesOnlyToggle / makeSidebarGitReader（旧 makeSidebarGitStatusLoader）は ViewerWindowAssembler.swift。

対応:
- makeViewMenuItem(isChangedFilesOnlyAvailable:isTreeLayoutAvailable:) / addSidebarItems(to:isChangedFilesOnlyAvailable:isTreeLayoutAvailable:) を追加し、その場の if FeatureGate.isSidebarGitStatusEnabled を addChangedFilesOnlyItem(to:isChangedFilesOnlyAvailable:) へ切り出した（addSidebarTreeLayoutItem と同じ形）。
- ViewerWindowAssembler.makeSidebarGitReader(fileIndex:statusStore:isGitStatusAvailable:) / makeChangedFilesOnlyToggle(for:isChangedFilesOnlyAvailable:) もゲート値を引数で受ける形へ揃えた（後者はテストから呼ぶため private → internal）。
- 既定値は既存の露出点（addDisplayModeItems / addSidebarTreeLayoutItem / SidebarDisplayPreference）と揃えて FeatureGate.* のデフォルト引数。よって .swiftlint.yml の excluded は既存のまま実態と一致し、FeatureGateEnumerationTests も無変更で通る（doc 側のシグネチャ表記だけ追随させた）。
- makeViewMenuItem が function_body_length を超えたため、履歴の前後移動を addHistoryItems(to:) へ切り出した。

検証（実測）:
- swift test: 1483 tests / 235 suites すべて成功。
- 変異テスト: ゲート判定を無効化（guard true / statusStore を素通し / guard 削除）すると、新規 3 テストの OFF 側が全て失敗することを確認した。
- swiftlint: 変更ファイル（MainMenuBuilder+ViewMenu / ViewerWindowAssembler / FeatureGate / MainMenuBuilderTests / 新規テスト）の警告ゼロ。swiftformat は 0 files formatted。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバー git ステータスゲートの露出点 3 箇所（View メニュー項目・ヘッダーのトグル・git 状態リーダー）を、その場で FeatureGate を読む形からゲート値の引数注入へ揃えた。ON/OFF 両方向を MainMenuBuilderTests と新規 ViewerWindowAssemblerGateTests で検証し、修正を戻すと OFF 側が落ちることも確認した（swift test 1483 件成功）。
<!-- SECTION:FINAL_SUMMARY:END -->
