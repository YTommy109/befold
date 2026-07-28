---
id: TASK-184
title: コードフォント設定のフィーチャーゲートを解除して stable に昇格する
status: To Do
assignee: []
created_date: '2026-07-28 13:57'
labels: []
dependencies:
  - TASK-181
ordinal: 264000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-181 で実装したソースコードビューのフォント設定は、開発中は FeatureGate.inProgressFeaturesEnabled で囲われ dev/DEBUG ビルドのみに露出している（TASK-180 のゲート機構）。機能が安定したと判断した時点で、このゲート分岐を撤去し stable ビルドでも露出させる。フィーチャーゲートは一時的な足場であり撤去し忘れると stable に機能が出ないままになるため、解除忘れ防止として本タスクを登録する。着手条件: TASK-181 が完了し、フォント設定機能を stable リリースに載せてよいと判断できること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 設定メニュー・設定ウィンドウを露出する FeatureGate.inProgressFeaturesEnabled の分岐が撤去され、stable ビルドでもコードフォント設定が露出する
- [ ] #2 この機能に固有のフィーチャーゲート参照がコードベースから残らず消えている（他機能がゲートを使っていなければゲート機構自体の要否も検討する）
- [ ] #3 撤去後もフォント設定のユニットテスト・ライブ反映が従来どおり動作する
<!-- AC:END -->
