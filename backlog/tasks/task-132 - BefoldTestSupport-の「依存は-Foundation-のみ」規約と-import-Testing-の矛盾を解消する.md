---
id: TASK-132
title: BefoldTestSupport の「依存は Foundation のみ」規約と import Testing の矛盾を解消する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:23'
updated_date: '2026-07-25 07:27'
labels:
  - test
  - docs
dependencies: []
priority: low
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で確認(CONFIRMED)。BefoldTestSupport/Waiting.swift:2 が import Testing しており(Issue.record、SourceLocation、TimeLimitTrait を使用)、.claude/CLAUDE.md の「BefoldTestSupport: 依存は Foundation のみ」と Package.swift(87-89 行)の「依存は Foundation のみに保つこと」に矛盾する。
非テストターゲットが将来 BefoldTestSupport をリンクすると swift-testing をテストホスト外に引き込み link/load 時に失敗するし、ドキュメントからターゲット構成を計画する読者を誤導する。Testing 依存ヘルパーを別ファイル/ターゲットへ移すか、両ドキュメントの規約を実態に合わせて更新するかを決めて解消する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 コード(import Testing)とドキュメント(CLAUDE.md / Package.swift コメント)の矛盾が解消されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 実態(Waiting.swift のみが Testing を使い、参照元はテストターゲットのみ)を確認する
2. ターゲット分割ではなく規約側を実態に合わせる: Package.swift のコメントと .claude/CLAUDE.md を『依存は Foundation と Testing(swift-testing)のみ。テストターゲットからのみリンクすること』へ更新する
3. 意図(GUI 本体 / BefoldRenderKit を持ち込まない)が読み取れる表現を維持する
4. swift build / swift test で確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査: Testing を import しているのは BefoldTestSupport/Waiting.swift のみ(Issue.record / SourceLocation / TimeLimitTrait を使用)。BefoldTestSupport を参照しているのは befoldTests / befoldCLITests の 2 つのテストターゲットだけ(Package.swift 96, 105 行)。

判断: ターゲット分割ではなく規約側を実態へ合わせた。待機ヘルパーは失敗を Issue.record で報告することが設計上の要点(呼び出し側の #expect 書き忘れを防ぐ)であり、Testing 依存は本質的。分割してもすべての利用側がテストターゲットである現状では利点がなく、ターゲットが増えるだけになるため。

変更:
- Package.swift: 『依存は Foundation と Testing(swift-testing)のみ。Testing はテストホスト外では解決できないためリンクはテストターゲットに限る』へ更新。元の意図(GUI 本体 / BefoldRenderKit を持ち込まない)は明示のまま維持し、BefoldKit も対象に加えた。
- .claude/CLAUDE.md: 同様に『依存は Foundation と Testing のみ(テストターゲットからのみリンクする)』へ更新。

検証: swift build 成功、swift test 全体 646 tests / 93 suites パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldTestSupport の依存規約を実態(Foundation + Testing、リンクはテストターゲットのみ)に合わせて Package.swift のコメントと .claude/CLAUDE.md を更新し、コードとドキュメントの矛盾を解消した。Testing 依存は待機ヘルパーの Issue.record 報告に不可欠でターゲット分割の実利がないため、分割ではなく規約更新を選択。swift build / swift test 646 tests パスで確認。
<!-- SECTION:FINAL_SUMMARY:END -->
