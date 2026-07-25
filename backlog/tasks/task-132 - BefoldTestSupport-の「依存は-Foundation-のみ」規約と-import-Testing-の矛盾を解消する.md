---
id: TASK-132
title: BefoldTestSupport の「依存は Foundation のみ」規約と import Testing の矛盾を解消する
status: To Do
assignee: []
created_date: '2026-07-24 22:23'
labels:
  - test
  - docs
dependencies: []
priority: low
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で確認(CONFIRMED)。BefoldTestSupport/Waiting.swift:2 が import Testing しており(Issue.record、SourceLocation、TimeLimitTrait を使用)、.claude/CLAUDE.md の「BefoldTestSupport: 依存は Foundation のみ」と Package.swift(87-89 行)の「依存は Foundation のみに保つこと」に矛盾する。
非テストターゲットが将来 BefoldTestSupport をリンクすると swift-testing をテストホスト外に引き込み link/load 時に失敗するし、ドキュメントからターゲット構成を計画する読者を誤導する。Testing 依存ヘルパーを別ファイル/ターゲットへ移すか、両ドキュメントの規約を実態に合わせて更新するかを決めて解消する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 コード(import Testing)とドキュメント(CLAUDE.md / Package.swift コメント)の矛盾が解消されている
<!-- AC:END -->
