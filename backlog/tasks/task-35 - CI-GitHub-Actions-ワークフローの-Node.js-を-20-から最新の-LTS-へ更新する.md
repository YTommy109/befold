---
id: TASK-35
title: 'CI: GitHub Actions ワークフローの Node.js を 20 から最新の LTS へ更新する'
status: To Do
assignee: []
created_date: '2026-07-17 02:05'
labels:
  - ci
  - chore
dependencies: []
priority: low
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI 実行時に "Node.js 20 is deprecated." という警告が出ている。.github/workflows/ci.yml:67 で actions/setup-node@v4 に node-version: '20' を固定指定している箇所が対象。GitHub Actions 側で Node 20 のサポート終了が予告されているため、将来のジョブ失敗を避けるために最新の LTS バージョンへ更新する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ci.yml の node-version を現行の Node.js LTS バージョンへ更新する
- [ ] #2 CI を実行し、Node.js 関連のステップが問題なく通ることを確認する
- [ ] #3 "Node.js 20 is deprecated" 警告が CI ログに出なくなることを確認する
<!-- AC:END -->
