---
id: TASK-100
title: 複数パスが別ウィンドウで開く挙動のヘルプ記述を復活させる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-22 13:38'
updated_date: '2026-07-22 14:06'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/BefoldRootCommand.swift
priority: medium
type: docs
ordinal: 89000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(inselberg-ramada ブランチ)で検出。TASK-94.4 でルート discussion の「ファイル/フォルダーを指定すると、それぞれ別ウィンドウで開きます」を削除したが、挙動を変える予定だった TASK-94.2 はキャンセルされ複数ウィンドウ挙動は維持された。現在ルートにも `befold open --help` にもウィンドウ挙動の記述がなく、複数パス指定でウィンドウが大量に開くことを事前に知る手段がない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `befold open --help`(または適切な場所)に複数パス指定時のウィンドウ挙動が記載される
- [x] #2 ヘルプ文言の回帰テストが更新される
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
OpenPathsCommand.discussion に 'Each path opens in its own window.' を追記。openDiscussionDescribesMultipleWindowBehavior テストで回帰検証。swift test 全パス。
<!-- SECTION:FINAL_SUMMARY:END -->
