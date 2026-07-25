---
id: TASK-140.2
title: render() の型分岐(svg/image/pdf/html)を DOM ビルダーへ抽出する
status: To Do
assignee: []
created_date: '2026-07-24 22:42'
labels:
  - refactor
  - structural
  - js
dependencies:
  - TASK-140.1
parent_task_id: TASK-140
priority: medium
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
render()(viewer-main.js:978-1133, 155行)の 9 分岐型ディスパッチのうち svg/image/pdf/html 分岐が viewer.js の buildTableHtml/renderCodeHtml/csvRowsHtml と同じ純粋ビルダー抽出パターンから漏れてインライン DOM 構築している。各分岐を _renderSvg/_renderImage/_renderPdf/_renderHtml(可能な部分は viewer.js 側の純粋 HTML ビルダー)へ切り出し、render() を型→ヘルパー選択+共通オーケストレーション(mermaid/annotate/find/zoom/scroll)に縮小する。TASK-140.1 のエクスポート境界導入が前提。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 svg/image/pdf/html の各分岐がヘルパー関数へ抽出され、純粋化可能な部分は viewer.js の HTML ビルダーとして単体テストされている
- [ ] #2 render() 本体が型ディスパッチ+共通オーケストレーションに縮小している
- [ ] #3 各型の描画(mmd/svg/html/csv/image/pdf/code/md)に回帰がない(webview-smoke + 手動確認)
<!-- AC:END -->
