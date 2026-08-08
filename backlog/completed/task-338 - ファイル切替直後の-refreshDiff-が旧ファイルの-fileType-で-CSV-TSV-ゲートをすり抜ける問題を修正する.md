---
id: TASK-338
title: ファイル切替直後の refreshDiff が旧ファイルの fileType で CSV/TSV ゲートをすり抜ける問題を修正する
status: Done
assignee: []
created_date: '2026-08-06 05:34'
updated_date: '2026-08-06 06:30'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 510000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/diff_view のコードレビュー（多段検証付き、CONFIRMED）で検出。

capabilities.canToggleDiff は store.fileType から導出される（ViewerWindowController.swift:716）が、fileType は非同期のコンテンツロード完了後に ViewerStore.apply() で確定する遅延値。ファイル切替中に git-status apply（.git/index の監視や他ウィンドウの保存）が届くと、fileURL は既に新ファイルを指すのに、ゲート判定は旧ファイルの型で通る。

再現シナリオ: .swift 表示中（canToggleDiff true）に差分表示 ON でサイドバーから変更済み .csv へ切り替える。CSV のロード確定前に git-status apply が届くと、refreshDiff が stale な .code 型でガードを通過し、TASK-324（d99159e9）が止めたはずの CSV への git diff サブプロセスを起動する。fileURL == url ガードも通るため、描画されることのない CSV の差分が store.diffText に保持される。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ファイル切替中に差分更新契機が届いても、切替先ファイルの種別で CSV/TSV ゲートが判定される
- [x] #2 この競合（ロード確定前の git-status apply）を再現する回帰テストがあり、修正を戻すと落ちる
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerCapabilities へ渡す supportsDiffDisplay を store.fileType（ロード完了まで旧ファイルの値）ではなく現在の fileURL から導く FileType(url:) に変更し、ファイル切替中に届いた取得契機でも切替先の種別でゲートするようにした。回帰テスト gatesByDestinationFileTypeDuringSwitch は修正前に reader.callCount==2 で落ち、修正後に 0 で通る（swift test 1171 件グリーン）。
<!-- SECTION:FINAL_SUMMARY:END -->
