---
id: TASK-73.5
title: check サブコマンドで befold が開けるファイルかどうかを確認できるようにする
status: To Do
assignee: []
created_date: '2026-07-19 09:11'
labels: []
dependencies:
  - TASK-73.1
parent_task_id: TASK-73
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLM エージェントが事前に「このファイルは befold で開けるか」を判断できるよう、
`befold check <path>` サブコマンドを追加する。既存の対応フォーマット判定ロジック
(FileType 等)を再利用し、専用の判定ロジックを新設しない方針で単純化を検討すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold check <path> で befold が開けるファイルかどうかを判定して結果を表示する
- [ ] #2 結果にファイルサイズを含める
- [ ] #3 結果にファイル型(拡張子/判定された FileType など)を含める
- [ ] #4 開けないファイル（未対応フォーマット、サイズ超過等）の場合は理由を表示する
- [ ] #5 存在しないパスを指定した場合はエラーメッセージを表示して終了する
<!-- AC:END -->
