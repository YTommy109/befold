---
id: TASK-908
title: 'PR #750（タブ操作・複数ファイルのドロップ・Reload の修正）を最新の main で CI を通して取り込む'
status: To Do
assignee: []
created_date: '2026-11-07T06:38:00Z'
labels:
  - pr
  - ci
dependencies: []
references:
  - https://github.com/YTommy109/befold/pull/750
priority: high
ordinal: 874000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #750 は基本的にそのまま取り込み、気になる点は取り込み後にこちらで直す方針にした（後続タスクはこのタスクへの依存で順序を表す）。PR の CI は head 7f7d8895 と当時の main（feddec71）で走っており、その後 main は 11 コミット進んだ（CSV 表示の変更と、#761 の PDF テスト分離を含む）。2026-11-07 時点で merge-tree は衝突なし、変更ファイルの重なりも無く、mergeStateStatus も CLEAN だが、重ねた状態のテストは走っていない。maintainerCanModify は true なので、こちらから PR ブランチを更新できる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PR の head に最新の main を含めた状態で CI の build-and-test（default / strict）と js-test、Site CI の test が成功している
- [ ] #2 PR #750 が main へマージされている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実機確認（2026-11-07、head 7f7d8895 を Xcode 27.2 SDK の Debug でビルド、設定は分離）: Finder からのドロップ（空タブ置換・複数ファイルの順序・重複防止・未対応形式の拒否・サイドバー上・空タブで既存ファイル）、Reload 後に本文が残る、直接 HTML のリンクとフォームの遮断、すべて期待どおり。ウィンドウ間のタブ移動は未確認。
<!-- SECTION:NOTES:END -->
