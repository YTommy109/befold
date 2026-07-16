---
id: TASK-1.1
title: レンダリングコア（WKWebView 構成〜render 適用）を BefoldKit へ抽出する
status: To Do
assignee: []
created_date: '2026-07-16 00:38'
updated_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/209
parent_task_id: TASK-1
ordinal: 17100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #209 から移行。ViewerWebView.swift（657行）に固着しているWKWebView構成・viewer.htmlロード・render()評価の組み立て役を BefoldKit に最小コンポーネント（ViewerRenderer）として新設する。find/loadMore/リンク遷移などアプリ専用機能はフック注入構造にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 WKWebView構成→viewer.htmlロード→renderScript評価だけを行う最小コンポーネントが BefoldKit に存在する
- [ ] #2 アプリ専用機能（find/loadMore/リンク遷移等）がフック注入で追加される構造になっている
- [ ] #3 Bundle.rendering が BefoldKit に移設されている
<!-- AC:END -->
