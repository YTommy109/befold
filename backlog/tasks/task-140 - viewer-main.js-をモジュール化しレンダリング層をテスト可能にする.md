---
id: TASK-140
title: viewer-main.js をモジュール化しレンダリング層をテスト可能にする
status: Done
assignee: []
created_date: '2026-07-24 22:41'
updated_date: '2026-07-25 03:03'
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
- [x] #1 (サブタスクで達成)viewer-main.js の命令的レンダリング層が jsdom + viewer.html DOM 下で import/単体テスト可能になっている
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
3 つのサブタスクで達成。viewer-main.js に viewer.js と同型のエクスポート境界を導入して読み込み時副作用を _mmdInit() へ分離し(140.1)、render() の型分岐を DOM ビルダーへ抽出して 155 行 → 69 行に縮小し(140.2)、find の共有グローバル状態を _createFindController() のクロージャへ閉じて順序依存を明示的な受け渡しにした(140.3)。0% だった命令的レンダリング層は jsdom(runScripts: 'outside-only')+ viewer.html の DOM 上で import・単体テストできるようになり、viewer-main.js 向けのテストを 45 件追加した(JS テスト全体 220 → 266)。各サブタスクで swift test 615 passed / webview-smoke PASS / 実アプリでの目視確認を実施済み。
<!-- SECTION:FINAL_SUMMARY:END -->
