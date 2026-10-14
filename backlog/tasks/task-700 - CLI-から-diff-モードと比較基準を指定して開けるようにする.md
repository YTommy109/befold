---
id: TASK-700
title: CLI から diff モードと比較基準を指定して開けるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-10-12 13:07'
updated_date: '2026-10-14 12:18'
labels:
  - cli
  - diff
dependencies: []
priority: medium
type: feature
ordinal: 889000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI の表示モード指定は CLIOpenOptions.sourceMode (Bool?) で、--source/--preview の 2 値しか表せない。ViewerDisplayMode には .diff があり比較基準 (GitComparisonTarget) も選べるが、どちらも GUI の View メニューからしか到達できない。スクリプトや他ツールから「差分で開く」ことができない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `--diff` で diff モードで開ける（`--source`/`--preview` と同時指定はパース段階でエラー）
- [x] #2 比較基準を指定する `--compare <target>` がある（`--diff` 無しの単独指定の扱いを決めて validate で明示する）
- [x] #3 sourceMode: Bool? を displayMode: ViewerDisplayMode? に置き換える。CLI と本体のバージョンずれ時の挙動（旧 CLI が sourceMode を送る場合）を CLIRequestWire のテストで担保する
- [x] #4 パス必須・--check/--bookmark 併用不可の制約が既存オプションと揃っている（BefoldCLIOptionValidationTests）
- [x] #5 README(ja/en)・docs/dev/cli-launch.md・site の CLI 記述を更新する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit: CLIDisplayModeOption(rendered/source/diff) と CLIComparisonTargetOption(parent-branch/default-branch/head) を CLISortOrderOption と同じ流儀で追加（ViewerDisplayMode/GitComparisonTarget は本体側にあり BefoldKit から見えないため写像を本体に置く）
2. CLIOpenOptions: sourceMode: Bool? を displayMode に置換、comparisonTarget を追加。Codable は独自 init(from:) で旧 sourceMode キーを displayMode へ読み替える（旧 CLI→新本体）。新→旧は displayMode 不明キーが無視され既定表示になる（許容、Notes に明記）
3. OpenCLIOptions: SourceModeFlag に diff を足して 3 値の排他フラグにする（--source/--preview/--diff 同時指定はパース段階エラー）。--compare は Option。validate: --compare は --diff 必須（単独指定はエラー）。requiresPaths に displayMode/comparisonTarget を含める
4. 本体: ViewerDisplayOptionsApplier と ViewerWindowController init の sourceModeOverride を displayModeOverride に置換し、comparisonTarget → displayMode の順で適用（setComparisonTarget は唯一の入口）
5. テスト: BefoldCLIOptionValidationTests / CLIRequestWireTests（旧 JSON 読み替え）/ 本体側の適用テスト
6. README(ja/en)・cli-launch.md・site の CLI 記述更新
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手前に /review-design を回す（ワイヤ形式の変更を含むため）。調査: 2026-10-12 のサブエージェント実査（実装読みのみ、--help 実出力は未確認）。

/review-design 実施(2026-10-14): sourceMode の読み手は ViewerDisplayOptionsApplier / ViewerWindowController.init / ViewerWindowManager+OpenViewer / テスト群の 4 系統（SessionRestorer は options を素通し）。.diff の縮退は ViewerDisplayMode.supported(for:)(FileType.supportsDiffDisplay)が既に持つので新設しない。旧 JSON 読み替え・排他・--compare 単独のテストで担保。ViewerWindowController 型グループは 940 行（改名+引数1つの追加に留める）。

決定: --compare は --diff 必須（単独はエラー）。旧 CLI の sourceMode は displayMode へ読み替え（CLIRequestWireTests）。新CLI→旧本体は displayMode が無視され既定表示になる（許容）。検証: swift test 全体 2043+81 件 pass、比較基準の適用を外すと新規テストが落ちることを確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
sourceMode: Bool? を displayMode(rendered/source/diff) に置換し --diff と --compare <parent-branch|default-branch|head> を追加。旧 CLI の sourceMode はデコード時に読み替え。適用は ViewerDocumentPresenter.applyCLIDisplay に一本化。README ja/en・cli-launch.md・site を更新。swift test 全件 pass で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
