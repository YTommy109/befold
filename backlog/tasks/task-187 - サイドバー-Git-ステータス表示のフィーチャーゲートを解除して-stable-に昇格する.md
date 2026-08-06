---
id: TASK-187
title: サイドバー Git ステータス表示のフィーチャーゲートを解除して stable に昇格する
status: To Do
assignee: []
created_date: '2026-07-28 14:23'
updated_date: '2026-08-05 16:16'
labels: []
dependencies:
  - TASK-186
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-git-status-design.md
priority: low
ordinal: 600000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-186（Phase1〜3）が dev で dogfood され安定したら、サイドバー Git ステータス表示を包む if FeatureGate.inProgressFeaturesEnabled 分岐を撤去し、常時有効にする。task-184（フォント設定のゲート解除）と同種の解除忘れ防止タスク。FeatureGate 機構（task-180）実装が前提。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバー Git ステータス表示の露出を包む FeatureGate 分岐が撤去され、stable ビルドで常時表示される
- [ ] #2 撤去後もユニットテスト・手動チェックが通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-03: 追加された TASK-263（フォルダー行の集約バッジ）/ TASK-264（変更ファイルのみ表示フィルター）も同じ FeatureGate 配下に入る。解除時は makeSidebarGitStatusLoader の guard に加えて TASK-264 のトグル UI 側のゲート分岐も撤去対象になる。

2026-08-06: ユーザー方針により、git 系機能が充実するまで着手しない。着手条件: ソース表示の git 差分（TASK-316〜322 の修正を含む）など同じ FeatureGate 配下の git 系機能が出揃い、サイドバー Git ステータスと合わせて stable 昇格をまとめて判断できる状態になったら再開する。
<!-- SECTION:NOTES:END -->
