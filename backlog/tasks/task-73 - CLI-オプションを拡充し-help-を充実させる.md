---
id: TASK-73
title: CLI オプションを拡充し --help を充実させる
status: To Do
assignee: []
created_date: '2026-07-19 09:10'
labels: []
dependencies: []
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 befold CLI シム(CLIInstaller.shimScriptContents)は `exec open -a <bundle> "$@"` のみで、
ファイルパス以外のオプション引数を受け取れない。LLM エージェント(Claude Code など)が
シェル経由で befold を操作しやすくするため、CLI オプション・サブコマンドを拡充し、
--help の usage を充実させる。詳細は各サブタスクで扱う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold --help で全オプション・サブコマンドの usage が一覧できる
- [ ] #2 複数ファイル/フォルダを指定した場合は複数ウィンドウで開く
- [ ] #3 表示オプション(隠しファイル表示・並び順・行番号表示・ソース/プレビューモード)を CLI から指定できる
- [ ] #4 bookmark サブコマンドでブックマークを追加できる
- [ ] #5 check サブコマンドで befold が開けるファイルかどうかとファイルサイズ・型などの詳細を確認できる
<!-- AC:END -->
