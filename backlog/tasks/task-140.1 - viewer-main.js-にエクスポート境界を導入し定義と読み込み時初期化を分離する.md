---
id: TASK-140.1
title: viewer-main.js にエクスポート境界を導入し定義と読み込み時初期化を分離する
status: To Do
assignee: []
created_date: '2026-07-24 22:42'
labels:
  - refactor
  - structural
  - js
dependencies: []
parent_task_id: TASK-140
priority: medium
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
viewer-main.js に typeof module ガード付きのエクスポート面を設け(viewer.js と同型)、定義と読み込み時の初期化呼び出し(_mmdInit*() 等)を分離して、jsdom + viewer.html DOM 下でロジックを import 可能にする。以降のサブタスク(render 分岐抽出・find 状態カプセル化)のテスト到達点の前提。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer-main.js が typeof module ガード付きでロジックをエクスポートし、副作用(即時 DOM 取得/リスナ登録)が初期化関数へ分離されている
- [ ] #2 jsdom で viewer-main.js を import してもトップレベル副作用でエラーにならず、少なくとも 1 つの関数が単体テストから呼べる
- [ ] #3 ブラウザ(WKWebView)での既存挙動に回帰がない(webview-smoke 通過)
<!-- AC:END -->
