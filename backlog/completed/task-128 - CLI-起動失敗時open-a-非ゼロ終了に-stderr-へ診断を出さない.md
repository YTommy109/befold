---
id: TASK-128
title: CLI 起動失敗時(open -a 非ゼロ終了)に stderr へ診断を出さない
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:22'
updated_date: '2026-07-25 07:05'
labels:
  - cli
  - bug
dependencies: []
priority: medium
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で確認(CONFIRMED)。befold-cli/CLIAppLauncher.swift:79 で /usr/bin/open -a が非ゼロ終了したとき、run() は raw status をそのまま返し stderr に何も書かない(直下の throw 経路は writeError でメッセージを書くのと非対称)。
befold.app が削除・破損している状態で `befold diagram.mmd` を実行すると、非ゼロ exit だが出力ゼロで、パス間違いなのかアプリ欠落なのか転送失敗なのか判別できない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 open -a 非ゼロ終了時に原因が分かるメッセージを stderr へ出力する
- [x] #2 この経路のテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 起動失敗の 2 経路(throw / open -a 非ゼロ終了)を同一の診断メッセージ形式に揃える
2. 非ゼロ終了時に bundlePath と終了コードを含むメッセージを stderr へ出力し、終了コードは従来どおり status を返す
3. befoldCLITests に非ゼロ終了時の stderr 出力テストを追加する
4. swift test で検証する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: CLIAppLauncher.run の open -a 非ゼロ終了経路で writeError にメッセージ(bundlePath + 終了コード + アプリ欠落/破損の示唆)を出力。throw 経路も bundlePath を含む同形式に揃え、2 経路の診断を非対称でなくした。終了コードは従来どおり raw status を返す(情報量を維持)。
検証: befoldCLITests に launchNonZeroExitWritesStderrMessage を追加(stderr に 'Failed to launch app' / bundlePath / status 42 が含まれることを検証)。swift test 全体 643 tests / 91 suites パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
open -a が非ゼロ終了したときに stderr へ 'Failed to launch app at <bundlePath>: open exited with status <N>. The app bundle may be missing or damaged.' を出力するようにし、throw 経路のメッセージも bundlePath を含む同形式へ統一した。befoldCLITests の新規テスト launchNonZeroExitWritesStderrMessage と swift test 全体(643 tests)パスで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
