---
id: TASK-1.12
title: postMessage ブリッジのゲートと CSP unsafe-inline 削除で多層防御する
status: To Do
assignee: []
created_date: '2026-07-18 13:41'
updated_date: '2026-07-18 13:42'
labels: []
dependencies:
  - TASK-1.7
parent_task_id: TASK-1
priority: medium
type: enhancement
ordinal: 1160
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セキュリティレビュー（2026-07-18）の M-1/M-2（推奨、task-1.7 の多層防御）。(M-1) referenceActivated/loadMoreLines は hostFeatures ゲート対象外で常時有効（ViewerWebView.swift:145-151,226-231, viewer.html:66-70）。QuickLook 拡張ではこれらを登録せず、hostFeatures にリンク遷移無効フラグを追加し JS 側でも抑止する。(M-2) CSP script-src 'unsafe-inline'（viewer.html:13）が H-1 サニタイザのバックストップを無効化している。要因は viewer.html:56-1198 の大きなインライン <script>。インライン script を外部化 or nonce 付与し unsafe-inline を削除して、XSS 混入時もインラインイベントハンドラを CSP で遮断できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 QuickLook 拡張で referenceActivated/loadMoreLines が登録されずリンク遷移が抑止される
- [ ] #2 CSP から script-src 'unsafe-inline' が削除され、インライン script が外部化 or nonce 化されている
- [ ] #3 アプリ本体の既存操作（リンク遷移・ズーム・検索・Load More）に回帰がない
<!-- AC:END -->
