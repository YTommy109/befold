---
id: TASK-702
title: CLI から新規窓で開けるようにする (--new-window)
status: Done
assignee:
  - '@claude'
created_date: '2026-10-12 13:08'
updated_date: '2026-10-14 12:18'
labels:
  - cli
dependencies: []
priority: low
type: feature
ordinal: 891000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI 経路は OpenDisposition が既定の .currentTab に固定（DocumentOpener）で、窓の再利用は ViewerWindowOpenPolicy 任せ。再利用せず新規窓で開きたい場合に CLI から選べない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `--new-window` で OpenDisposition.newWindow により開ける
- [x] #2 パス必須の制約と --check/--bookmark 併用不可が既存オプションと揃っている
- [x] #3 ワイヤ形式に追加する場合、旧 CLI/旧本体との組み合わせでの挙動をテストで担保する
- [x] #4 README・docs/dev/cli-launch.md を更新する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIOpenOptions に opensInNewWindow: Bool（既定 false、decodeIfPresent で旧 JSON 互換）を追加。disposition は CLIRequest の形を変えず options に載せる
2. OpenCLIOptions に --new-window フラグ。requiresPaths に含めるのでパス必須・--check/--bookmark 併用不可は既存の validate が自動で効く
3. DocumentOpener.openPaths → openViewer に disposition(.newWindow) を通す（ViewerWindowManager.openViewer は既に disposition を受け ViewerWindowOpenPolicy.reusableController が .newWindow を再利用しない）
4. テスト: validation / wire（旧 JSON で false） / ViewerWindowOpenPolicy 経由で同一ファイルでも新規窓
5. README・cli-launch.md 更新
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
--new-window を追加。CLIOpenOptions.opensInNewWindow(旧 JSON は false)を CLIOpenOptions.openDisposition で OpenDisposition.newWindow に写し DocumentOpener.openPaths に通す。validate は requiresPaths に含めて既存制約と揃えた。テスト(validation / wire / 同一ファイルでも新規窓)と README・cli-launch.md 更新、swift test 全件 pass。
<!-- SECTION:FINAL_SUMMARY:END -->
