---
id: TASK-480.1
title: ADR 0002 にサイドバー表示 4 値の粒度と永続化の位置づけを追記する
status: To Do
assignee: []
created_date: '2026-08-14 08:01'
labels: []
dependencies: []
documentation:
  - docs/adr/0002-presentation-state-and-capabilities.md
parent_task_id: TASK-480
priority: high
type: docs
ordinal: 90100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバー表示 4 値を窓ごとのライブ値へ移すにあたり、ADR 0002 の「窓ごとのライブ値 / アプリ全体の設定」の線引きを更新する。永続化は app-global キーを新規ウィンドウの初期値として残す形とし、その位置づけ(ライブ値は窓、初期値はアプリ)を明記する。GlobalDisplayBroadcaster の doc コメントが述べる「ここから配ってよいもの」の定義も、この決定に合わせて書き換える対象として指す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ADR 0002 にサイドバー表示 4 値(layoutMode / showHiddenFiles / showChangedFilesOnly / sortOrder)が窓ごとのライブ値であることが記載されている
- [ ] #2 永続化された app-global 値は新規ウィンドウの初期値としてのみ使う、と ADR に明記されている
- [ ] #3 markdownlint-cli2 が通る
<!-- AC:END -->
