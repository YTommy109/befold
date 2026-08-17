---
id: TASK-485.8
title: stable ビルドの編集メニューに開発中のジャンプ項目が無効状態で常時表示される
status: To Do
assignee: []
created_date: '2026-08-17 14:02'
labels: []
dependencies: []
parent_task_id: TASK-485
priority: high
type: bug
ordinal: 714500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: PLAUSIBLE）

`MainMenuBuilder.addDocumentJumpItems`（`BefoldApp/befold/App/MainMenuBuilder.swift:162`）はセパレータと 2 つのジャンプ項目を無条件で挿入し、FeatureGate は検証（validation）でしか無効化しない。stable ビルド（ゲート閉）では `canJump` が常に false（`ViewerCapabilities.swift:80`）のため、ユーザーには「見出しへ移動 / 変更ブロックへ移動」が永久にグレーアウトした壊れた見た目で露出する。TASK-510 がゲートを再導入して防ごうとした露出そのもの。

撤去前のゲートはメニュー構築自体を `if FeatureGate.inProgressFeaturesEnabled` で包んで構築時に隠していた（コミット 85be3c9f）。隣接コメント（`MainMenuBuilder.swift:156-160`）は stable ユーザーへキーバインドを漏らさない意図を示す。一方 task-485.1 の J7 は意図的にゲートを capabilities へ移しており、visible-but-disabled が意図の可能性もある（verdict が PLAUSIBLE 止まりの理由）。

## 方針判断

visible-but-disabled が意図なら、その判断を記録して本タスクは閉じる。意図でなければ、ゲート閉時は項目の構築自体をスキップする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 stable ビルド（FeatureGate 閉）の編集メニューにジャンプ項目が表示されない、または表示する判断が理由付きで記録されている
- [ ] #2 dev ビルドでは従来どおり項目が表示・動作する
- [ ] #3 ゲート閉時の非表示をテストまたは構造（構築スキップ）で担保する
<!-- AC:END -->
