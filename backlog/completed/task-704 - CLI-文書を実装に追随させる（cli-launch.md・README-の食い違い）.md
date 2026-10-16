---
id: TASK-704
title: CLI 文書を実装に追随させる（cli-launch.md・README の食い違い）
status: Done
assignee:
  - '@claude'
created_date: '2026-10-12 13:08'
updated_date: '2026-10-14 12:10'
labels:
  - cli
  - docs
dependencies: []
priority: medium
type: chore
ordinal: 893000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI の見直し調査 (2026-10-12) で、docs/dev/cli-launch.md と README に実装とのずれが見つかった。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 cli-launch.md の責務表を実装に合わせる（宛先探索・再送・ACK 待ちは BefoldCLI 側。befold-cli は薄い入口）
- [x] #2 cli-launch.md の受信側の節を AppDelegate.handleCLIOpenRequest から AppCLIRequestReceiver に直す
- [x] #3 cli-launch.md の見出し「サブコマンド」を、実態（--check/--bookmark のフラグモード）に合う表現へ直す
- [x] #4 README(ja/en) に、--check/--bookmark と表示オプションの併用不可、および終了コード（0 成功 / 1 失敗）を追記する
- [x] #5 引数エラーの終了コードを実測してから書く（64 は推定）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 終了コードを befold-cli 実出力で測る 2. cli-launch.md の責務表・受信側・見出しを修正し終了コード節を追加 3. README ja/en に併用不可と終了コードを追記
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
終了コード実測(2026-10-14, 再ビルドした befold-cli): --bogus/--check(パス無し)/--check --bookmark x/--check --source x はすべて 64、--check /nonexistent は 1、--check README.md は 0。markdownlint-cli2 0 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
cli-launch.md の責務表・受信側(AppCLIRequestReceiver)・見出し(フラグモード)を実装に合わせ、終了コード節を追加。README ja/en に併用不可と終了コード(0/1/64、64 は実測)を追記。markdownlint-cli2 で 0 件を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
