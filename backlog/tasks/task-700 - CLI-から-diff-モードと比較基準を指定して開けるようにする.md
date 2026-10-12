---
id: TASK-700
title: CLI から diff モードと比較基準を指定して開けるようにする
status: To Do
assignee: []
created_date: '2026-10-12 13:07'
labels:
  - cli
dependencies: []
priority: medium
ordinal: 889000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI の表示モード指定は CLIOpenOptions.sourceMode (Bool?) で、--source/--preview の 2 値しか表せない。ViewerDisplayMode には .diff があり比較基準 (GitComparisonTarget) も選べるが、どちらも GUI の View メニューからしか到達できない。スクリプトや他ツールから「差分で開く」ことができない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `--diff` で diff モードで開ける（`--source`/`--preview` と同時指定はパース段階でエラー）
- [ ] #2 比較基準を指定する `--compare <target>` がある（`--diff` 無しの単独指定の扱いを決めて validate で明示する）
- [ ] #3 sourceMode: Bool? を displayMode: ViewerDisplayMode? に置き換える。CLI と本体のバージョンずれ時の挙動（旧 CLI が sourceMode を送る場合）を CLIRequestWire のテストで担保する
- [ ] #4 パス必須・--check/--bookmark 併用不可の制約が既存オプションと揃っている（BefoldCLIOptionValidationTests）
- [ ] #5 README(ja/en)・docs/dev/cli-launch.md・site の CLI 記述を更新する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手前に /review-design を回す（ワイヤ形式の変更を含むため）。調査: 2026-10-12 のサブエージェント実査（実装読みのみ、--help 実出力は未確認）。
<!-- SECTION:NOTES:END -->
