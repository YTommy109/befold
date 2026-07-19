---
id: TASK-73.1
title: CLI 引数パーサー基盤を整備し --help を充実させる
status: To Do
assignee: []
created_date: '2026-07-19 09:10'
labels: []
dependencies: []
parent_task_id: TASK-73
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 CLIInstaller.shimScriptContents は `exec open -a <bundle> "$@"` のみで、
open(1) の挙動上、追加引数がオプションフラグかファイルパスか区別できない
（open -a はファイル起動用の引数として扱う想定のため、フラグを渡すには
`--args` 経由でアプリ本体に引数を転送するようシム自体の見直しが必要になる可能性がある）。
このタスクでは、他サブタスクが実装する各種オプション・サブコマンドを受け止められる
引数パーサー基盤を用意し、`befold --help` で usage・オプション一覧・サブコマンド一覧を
表示できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold --help / -h で usage、各オプションの説明、各サブコマンドの説明が表示される
- [ ] #2 不明なオプション・サブコマンドを指定した場合はエラーメッセージと usage を表示して終了する
- [ ] #3 CLI シムがオプションフラグをファイルパスと区別してアプリ本体まで渡せる（open -a の制約がある場合はシムの起動方式を見直す）
- [ ] #4 既存のファイルパス指定での起動（フラグなし）が引き続き動作する
<!-- AC:END -->
