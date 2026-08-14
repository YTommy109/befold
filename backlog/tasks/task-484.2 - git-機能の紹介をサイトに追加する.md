---
id: TASK-484.2
title: git 機能の紹介をサイトに追加する
status: To Do
assignee: []
created_date: '2026-08-14 13:05'
updated_date: '2026-08-14 13:22'
labels: []
milestone: m-1
dependencies:
  - TASK-484.1
parent_task_id: TASK-484
priority: high
type: feature
ordinal: 707000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
v1.13.0 で stable になった git 連携をサイトの機能紹介に載せる。現在サイトには「git を知っているリンク解決」しか無く、差分表示とサイドバーの変更ファイル識別が紹介されていない。

**載せる（実装済み）**
- サイドバーの git ステータスバッジ — ファイル行に変更種別を 1 文字と色で表示、フォルダー行は配下の集約。staged / unstaged / untracked / branchModified を区別
- サイドバーの「変更ファイルのみ」表示
- ソース表示での差分表示 — ツールバーの 3 択（レンダリング / ソース / 差分）と `⌘1`〜`⌘3`、表示モードはファイル単位で永続化
- 差分レイアウトの上下・左右切替（`⌘\`、アプリ全体で共有）
- 「最近使ったリポジトリ」メニュー（worktree を階層表示）

**載せない（未実装）**
- レンダリング表示のままの差分表示（TASK-483）— 現在の差分はソース表示のみ
- 比較基準の切り替え UI（TASK-353）— 現在はデフォルトブランチとの merge-base に固定

文言は `site/src/views/shared.tsx` の `FEATURES` / `MORE_FEATURES` に足す（LP と /features が共に参照する単一情報源）。6 件ずつの現在の構成をどう組み替えるか（既存項目を `MORE_FEATURES` へ落として git を `FEATURES` へ上げるか等）はこのタスクで決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーで変更ファイルを識別できることが紹介されている
- [ ] #2 ソース表示で git 差分を見られることが紹介されている
- [ ] #3 差分がソース表示に限られること、比較基準が固定であることについて、実態と食い違う表現になっていない
- [ ] #4 文言が shared.tsx の共有定数として定義され、LP と /features の両方に反映される
- [ ] #5 日英の両方に同じ内容が入っている
<!-- AC:END -->
