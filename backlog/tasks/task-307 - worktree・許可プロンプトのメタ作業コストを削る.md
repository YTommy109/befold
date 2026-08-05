---
id: TASK-307
title: worktree・許可プロンプトのメタ作業コストを削る
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 17:05'
updated_date: '2026-08-05 14:01'
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
- [x] #1 worktree・ブランチ・PR・作業内容の対応を 1 コマンドで一覧できる手段があり、閉じたウィンドウの作業内容を会話なしで特定できる
- [x] #2 既存の /worktree-clean・/worktree-reset と役割が重複せず、使い分けが記述されている
- [x] #3 /fewer-permission-prompts 等で transcript を走査し、頻出する読み取り専用操作の許可設定が settings.json へ反映されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容

### AC#1 worktree の一覧（scripts/worktree-status.sh + /worktree-status）

読み取り専用スクリプトを新設。worktree ごとに『ブランチ名 / origin/main からのコミット数 / PR 番号と状態（gh）/ 未コミット変更の有無 / 最終コミットの日時と件名 / 絶対パス』を出す。

実測（5 worktree）: worktree 名とブランチ名が一致しないケース（claret-bighorn → dune-tumbleweed、monolith-haze → playa-dry）が実在し、これが『どの worktree か分からない』の直接の原因になっていた。最終コミット件名と未コミット変更の有無が出るため、閉じたウィンドウの作業内容を会話なしで特定できる。

検証: 5 worktree で期待どおり出力、--no-pr / 不正引数（exit 1）も確認。PR が無いブランチで '#null null' と出るバグを jq の .[0] → .[] で修正済み。bash -n / shellcheck ともにクリーン。

### AC#2 使い分け

/worktree-status の冒頭に 3 コマンドの対比表（status=調べる・変更なし / reset=worktree を残してブランチ切り直し / clean=worktree ごと削除）を置き、/worktree-clean・/worktree-reset の双方から status への導線を追記した。

### AC#3 許可設定

最近 50 セッションの transcript（3,830 tool_use）を走査し、頻出かつ読み取り専用で自動許可されていないものを .claude/settings.json の permissions.allow へ 18 件追加した。

- backlog CLI の読み取り系: instructions(52) / task view(18) / task list(17) / search(7)
- swift test(93) / swift build(5) / swiftformat の --lint 形（完全一致）
- markdownlint-cli2（完全一致。--fix は含めない）
- scripts/worktree-status.sh、scripts/worktree-clean.sh の dry-run 形
- dagayn MCP の読み取り系 6 種（CLAUDE.md がグラフ優先を指示しているため）
- Read(/private/tmp/claude-501/**)（スクラッチパッド）、Read(~/.claude/projects/*/memory/**)（memory ディレクトリ）— 起票時に挙がっていた許可プロンプトの発生源

除外したもの: git/gh/rg/grep/head/tail/cat/ls 等は Claude Code が既に自動許可（追加不要）。backlog task edit(62) / create(13) / git commit / add / push / osascript / PlistBuddy（引用符を含みパターンが壊れやすい）は変更を伴うか安全に書けないため入れていない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
worktree のメタ作業と許可プロンプトの反復コストを仕組みで削った。(1) scripts/worktree-status.sh と /worktree-status を新設し、ブランチ・PR・未コミット変更・最終コミット件名・パスを 1 コマンドで一覧できるようにした（worktree 名とブランチ名が一致しない実例が 2 件あり、これが特定コストの原因だった）。(2) 3 つの worktree コマンドの使い分け表を追加し、clean/reset の両方から導線を張った。(3) 最近 50 セッション・3,830 tool_use を走査し、読み取り専用で頻出する 18 パターンを .claude/settings.json へ追加した（memory ディレクトリとスクラッチパッドの Read を含む）。bash -n / shellcheck / markdownlint-cli2 すべてクリーン。
<!-- SECTION:FINAL_SUMMARY:END -->
