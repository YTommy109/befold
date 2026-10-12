---
id: TASK-704
title: CLI 文書を実装に追随させる（cli-launch.md・README の食い違い）
status: To Do
assignee: []
created_date: '2026-10-12 13:08'
labels:
  - cli
dependencies: []
priority: low
ordinal: 893000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI の見直し調査 (2026-10-12) で、docs/dev/cli-launch.md と README に実装とのずれが見つかった。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 cli-launch.md の責務表を実装に合わせる（宛先探索・再送・ACK 待ちは BefoldCLI 側。befold-cli は薄い入口）
- [ ] #2 cli-launch.md の受信側の節を AppDelegate.handleCLIOpenRequest から AppCLIRequestReceiver に直す
- [ ] #3 cli-launch.md の見出し「サブコマンド」を、実態（--check/--bookmark のフラグモード）に合う表現へ直す
- [ ] #4 README(ja/en) に、--check/--bookmark と表示オプションの併用不可、および終了コード（0 成功 / 1 失敗）を追記する
- [ ] #5 引数エラーの終了コードを実測してから書く（64 は推定）
<!-- AC:END -->
