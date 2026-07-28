---
id: TASK-192
title: コードフォント設定を stable 昇格しフィーチャーゲートを撤去する
status: To Do
assignee: []
created_date: '2026-07-28 15:50'
labels: []
dependencies:
  - TASK-181
ordinal: 275000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-181 のコードフォント設定を stable リリースに載せると決めた時点で、FeatureGate.inProgressFeaturesEnabled による分岐(MainMenuBuilder の設定メニュー項目のゲート)を撤去し、設定 UI をデフォルト露出にする。TASK-180 のフィーチャーゲート運用ルール(足場は stable 昇格時に撤去)に基づく。着手条件: コードフォント設定を stable に載せる意思決定が済むこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 設定メニュー/ウィンドウの FeatureGate 分岐が撤去され、stable ビルドでも露出する
- [ ] #2 FeatureGate が他の利用者を持たない場合は FeatureGate 自体の要否を再検討する
<!-- AC:END -->
