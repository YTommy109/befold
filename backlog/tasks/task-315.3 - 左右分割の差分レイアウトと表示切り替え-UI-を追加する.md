---
id: TASK-315.3
title: 左右分割の差分レイアウトと表示切り替え UI を追加する
status: To Do
assignee: []
created_date: '2026-08-05 14:46'
updated_date: '2026-08-05 14:47'
labels: []
dependencies:
  - TASK-315.2
parent_task_id: TASK-315
priority: medium
type: task
ordinal: 516000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 の 3 段目。インライン差分（2 段目）に加えて左右分割（side-by-side）を実装し、ユーザーが切り替えられるようにする。

論点:

- 切り替えの入口（表示メニュー / ツールバー / ショートカット）。既存のソース表示・行番号は `MainMenuBuilder.swift:177,181-182` と `ViewerToolbarController.swift` に入口がある
- 状態の持ち方（per-file の `SourceModeStore` 相当か、ウィンドウ/アプリ全体か）
- フォルダー提示中に操作が届かないこと。能力判断は `ViewerCapabilities` に集約済み（TASK-271）で、validateMenuItem・ツールバー・実行側がすべて同じ導出を見る
- FeatureGate: 機能ごとの別名プロパティを足し、`FeatureGate.swift` の露出点列挙コメントを更新する。`FeatureGateEnumerationTests` がソース走査と列挙を突き合わせるため、更新漏れはテストで落ちる
- コミットには `(gate)` スコープを付ける
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 左右分割レイアウトで、対応する行が左右で揃って表示される
- [ ] #2 左右分割とインラインをユーザーが切り替えられ、切り替え結果が意図した粒度で永続化される
- [ ] #3 フォルダー提示中は差分表示の操作がメニュー・ツールバーのいずれからも実行されない
- [ ] #4 FeatureGate 配下で dev/DEBUG のみ露出し、露出点列挙と FeatureGateEnumerationTests が更新されている
<!-- AC:END -->
