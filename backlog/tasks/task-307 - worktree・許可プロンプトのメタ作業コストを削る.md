---
id: TASK-307
title: worktree・許可プロンプトのメタ作業コストを削る
status: To Do
assignee: []
created_date: '2026-08-04 17:05'
labels: []
dependencies: []
priority: medium
ordinal: 493000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セッション実測で、人間の発話の 8.9% が worktree・ブランチ・PR の管理に費やされていた。特に「プルリクを作る前に作業環境を閉じてしまいました。どの worktree か調べてください」が複数セッションで繰り返し発生しており、そのたびに調査コストを払っている（worktree 別のセッションディレクトリは 132 個存在する）。

あわせて、許可プロンプト対策の発話も 4.5% あり（例: サブエージェントのファイルアクセス、/tmp の読み取り、memory ディレクトリの読み取り）、その多くは事後的に settings.json へ追記する形で潰されてきた。いずれも本題ではない反復コストなので、仕組みで消す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 worktree・ブランチ・PR・作業内容の対応を 1 コマンドで一覧できる手段があり、閉じたウィンドウの作業内容を会話なしで特定できる
- [ ] #2 既存の /worktree-clean・/worktree-reset と役割が重複せず、使い分けが記述されている
- [ ] #3 /fewer-permission-prompts 等で transcript を走査し、頻出する読み取り専用操作の許可設定が settings.json へ反映されている
<!-- AC:END -->
