---
id: TASK-95
title: bump.sh が AppVersion.current を更新せず次回リリースで確実にバージョンずれが起きる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-22 13:37'
updated_date: '2026-07-22 13:57'
labels: []
dependencies: []
references:
  - scripts/bump.sh
  - BefoldApp/befold/App/AppVersion.swift
priority: high
type: bug
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(inselberg-ramada ブランチ, /code-review high)で検出。scripts/bump.sh は project.yml の MARKETING_VERSION だけを sed で書き換えて即 commit/tag/push するため、TASK-94.1 で新設した AppVersion.current("1.7.2")は古いまま残る。次回 /bump 実行でリリース版の `befold --version` が旧バージョンを表示し、ドリフト検知テスト(projectYmlMarketingVersionMatchesAppVersionConstant)は bump フローでは実行されないため防げず、以後 main のテストが落ち続ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 bump.sh が MARKETING_VERSION と AppVersion.current を同時に書き換える
- [x] #2 bump フロー内でバージョンドリフト検知テスト(または swift test)が tag/push 前に実行される
- [x] #3 bump 後に `befold --version` と About 表示のバージョンが一致する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. bump.sh に AppVersion.swift の sed 書き換えを追加する 2. git add に AppVersion.swift を追加する 3. bump 後の swift test 実行は AC#2 で要求されているが、bump.sh は main ブランチ限定・CI 外で実行されるため、コメントで swift test の推奨のみ記載する方が実用的か検討する
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
bump.sh に AppVersion.swift の sed 書き換えを追加し、tag/push 前に swift test --filter projectYmlMarketingVersionMatchesAppVersionConstant を実行するようにした。全570ユニットテスト＋17インテグレーションテストがパス。
<!-- SECTION:FINAL_SUMMARY:END -->
