---
id: TASK-35
title: 'CI: GitHub Actions ワークフローの Node.js を 20 から最新の LTS へ更新する'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-07-17 02:05'
updated_date: '2026-07-17 08:51'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. .github/workflows/ci.yml:67 の node-version を '20' から '24'(現行 Active LTS) へ更新する
2. BefoldApp で npm ci / npm test をローカル実行し、Node 24 でも問題なく通ることを確認する
3. CI 実行結果で Node.js 20 deprecated 警告が消えていることを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ci.yml:67 の node-version を '20'→'24' に更新。ローカル Node 24.18.0 で npm ci / npm test を実行し、193 テスト全て成功を確認。CI 上での deprecated 警告解消確認は push 後に要実施。
<!-- SECTION:NOTES:END -->
