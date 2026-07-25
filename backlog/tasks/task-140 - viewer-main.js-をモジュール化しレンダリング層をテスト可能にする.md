---
id: TASK-140
title: viewer-main.js をモジュール化しレンダリング層をテスト可能にする
status: To Do
assignee: []
created_date: '2026-07-24 22:41'
updated_date: '2026-07-25 00:25'
labels:
  - refactor
  - structural
  - js
dependencies: []
priority: high
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
viewer-main.js(約1164行)は IIFE も module.exports も持たず全てグローバルスコープで、読み込み時に DOM 取得/addEventListener を即時実行するため jsdom で import できず、render/appendChunk/_mmdFind*/_mmdApplyZoom 等の命令的レンダリング層が 0% テスト。純粋側 viewer.js(テスト可能)との 2 分割はあるが不純側の全ロジックがテスト不能な壁の向こうに固定されている。render() は依存グラフのホットスポット(degree 58)でありながら 155 行の一枚岩で 9 分岐の型ディスパッチと DOM インライン構築・オーケストレーションが混在。Find サブシステムは 6 つの裸のモジュールグローバルと順序依存(_mmdModeJustSwitched/_lastChunkEndedWithNewline)の暗黙結合を持つ。エクスポート境界の導入(サブタスク1)を起点に、render の型分岐ビルダー抽出(2)・find/zoom 状態のカプセル化(3)へ分解する。構造レビュー(2026-07-25)で検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 (サブタスクで達成)viewer-main.js の命令的レンダリング層が jsdom + viewer.html DOM 下で import/単体テスト可能になっている
<!-- AC:END -->
