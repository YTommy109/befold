---
id: TASK-484.5
title: git 機能のスクリーンショットをカルーセルに追加する
status: To Do
assignee: []
created_date: '2026-08-14 13:06'
labels: []
dependencies:
  - TASK-484.2
parent_task_id: TASK-484
priority: medium
type: task
ordinal: 710000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LP のスクリーンショットカルーセル（`site/src/views/landing.tsx:16-34`）は現在 6 枚で、Mermaid / SVG / Markdown / CSV / Source Code / Quick Open。**git 差分表示とサイドバーの git ステータスの画像が無い。**

TASK-484.2 で文章として紹介する機能を、画像でも見せられるようにする。

- git 差分表示（ソース表示、左右分割と上下のどちらを見せるかは判断する）
- サイドバーの git ステータスバッジ（変更ファイルが識別できている状態）

カルーセルの項目は `kind` を持ち、ファイル形式でなく機能を示すものにはキャプションのラベルが付く（Quick Open が前例）。alt テキストは日英ページで共通に使われるため英語で書かれている。既存 6 枚と画質・ウィンドウサイズ・テーマを揃えること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git 差分表示のスクリーンショットがカルーセルにある
- [ ] #2 サイドバーで変更ファイルが識別できている状態のスクリーンショットがカルーセルにある
- [ ] #3 alt テキストとキャプションが既存項目の書き方に揃っている
- [ ] #4 画像のサイズ・テーマ・ウィンドウ寸法が既存 6 枚と揃っている
<!-- AC:END -->
