---
id: TASK-17
title: チャンク読み込み導入でファイル内検索が読み込み済み部分しかヒットしなくなった
status: To Do
assignee: []
created_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/198'
type: bug
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
チャンク読み込みにより初回 1000 行 / 1MB のみ DOM に載るため、Cmd+F が未読み込み部分にヒットしない。main では 10MB 未満のテキストは全量読み込み・全文検索可能だったため挙動の回帰。対応方針: (1) 検索時に全チャンク読み込み (2) 未読み込み領域の明示 (3) 意図したトレードオフとして設計ドキュメントに明記。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 検索時に全文が検索対象になる、または未読み込み領域があることが検索 UI に明示される
<!-- AC:END -->
