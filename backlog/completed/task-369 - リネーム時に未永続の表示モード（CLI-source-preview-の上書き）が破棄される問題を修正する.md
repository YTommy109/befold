---
id: TASK-369
title: リネーム時に未永続の表示モード（CLI --source/--preview の上書き）が破棄される問題を修正する
status: Done
assignee: []
created_date: '2026-08-08 11:22'
updated_date: '2026-08-08 12:07'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/ViewerWindowController.swift
priority: medium
type: bug
ordinal: 510000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) 指摘。handleRename が「サポート外になった場合のみリセット」（旧: `if isSourceMode, !supportsSourceMode { resetSourceMode() }`）を落とし、restoredDisplayMode(for: newURL) で保存値を無条件に再適用するようになった。このため永続化されていないライブなモード — 特に init 時に適用される CLI --source/--preview の上書き（「この起動限りの上書き」として保存値を意図的に触らない）— がリネームで破棄される。

再現: `befold --source note.md` で開く（保存値 .rendered、表示は source）→ mv / git checkout / エディタの save-via-rename でリネーム → セッション途中で source から rendered へ勝手に戻る（.md は source 表示をサポートしているのに）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 リネーム後も新 URL でサポートされる限り、現在表示中のモードが維持される
- [x] #2 新 URL でサポート外になった場合のみモードが降格する
- [x] #3 CLI 上書き（未永続モード）+ リネームのケースをユニットテストで担保する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DisplayModeStore.restoredDisplayMode の降格ロジックを supportedDisplayMode(_:for:) へ切り出し（restoredDisplayMode はその薄いラッパー）、handleRename が保存値ではなく「いま表示中のモード」(controller.displayMode) を渡すようにした。降格規則は 1 箇所のまま。検証: swift test 1207 tests / 177 suites すべて成功。swiftlint はベースライン差分ゼロ（変更ファイルの警告はいずれも変更前から存在）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
handleRename が保存値を再適用していたため、CLI --source/--preview による未永続のライブなモードがリネームで破棄されていた。降格規則を DisplayModeStore.supportedDisplayMode(_:for:) へ切り出し、リネーム時は現在表示中のモードを引き継いで新 URL で成立しない場合のみ降格するようにした。CLI 上書き + リネームの維持/降格の両方向をユニットテストで担保。swift test 1207 件全成功、swiftlint 差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
