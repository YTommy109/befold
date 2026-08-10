---
id: TASK-353
title: 差分の比較基準を「未コミットの変更」と「ブランチの変更」で切り替えられるようにする
status: To Do
assignee: []
created_date: '2026-08-07 05:24'
updated_date: '2026-08-10 13:57'
labels:
  - diff
dependencies: []
priority: medium
type: feature
ordinal: 113000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-352 で差分ビューアの比較基準をサイドバーのバッジと揃え、`git diff <merge-base HEAD defaultBranch>` にした。これにより「ブランチでの変更」が既定になる。

一方で「いま自分が編集した未コミットの変更だけを見たい」場面もあるため、2 つの基準を切り替えられるようにしたい。

- **ブランチの変更**: `merge-base HEAD <defaultBranch>` 基準（TASK-352 で既定にしたもの）
- **未コミットの変更**: `HEAD` 基準（TASK-352 以前の挙動）

設計で決めること:

- 切り替えの粒度（アプリ全体 / ウィンドウごと / ファイルごと）。`DiffDisplayPreference` は現在アプリ全体共有（TASK-319 で窓ごと生成の不具合を修正済み）なので、そこに合わせるのが自然
- UI の置き場（View メニュー / ツールバー / 差分パネル内）
- サイドバーのバッジ側も同じ基準に追従させるか。追従させないと TASK-352 で解消した食い違いが別の形で戻る
- 永続化するか、起動ごとに既定へ戻すか

着手前に `/review-design` を回すこと（新しい表示設定を足す変更のため）。

スコープは `FeatureGate.isSourceDiffEnabled` 配下。コミット件名には `(gate)` を付けること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 2 つの比較基準をユーザーが切り替えられる
- [ ] #2 切り替えの粒度が決まっており、それが破れたら落ちるテストがある
- [ ] #3 サイドバーのバッジと差分ビューアの基準が食い違わない（TASK-352 の一貫性が保たれる）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 優先順位の整理(2026-08-10)

TASK-435(git 連携の libgit2 移行)の後段に置いた(ordinal 113000)。本タスクは GitDiffLoader / 比較起点の解決に手を入れる feature であり、435 より先に着手するとバックエンド差し替え時に作り直しになる。435 の着手前に本タスクをやる場合は、その手戻りを承知の上で判断すること。
<!-- SECTION:NOTES:END -->
