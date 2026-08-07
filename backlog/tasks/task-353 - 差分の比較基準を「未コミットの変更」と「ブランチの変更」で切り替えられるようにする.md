---
id: TASK-353
title: 差分の比較基準を「未コミットの変更」と「ブランチの変更」で切り替えられるようにする
status: To Do
assignee: []
created_date: '2026-08-07 05:24'
labels:
  - diff
dependencies: []
priority: medium
type: feature
ordinal: 507000
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
