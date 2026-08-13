---
id: TASK-467
title: XDG 配置のグローバル gitignore が読まれず、無視すべきファイルが「変更されたファイルのみ表示」に出る
status: To Do
assignee: []
created_date: '2026-08-13 04:30'
updated_date: '2026-08-13 04:44'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 690000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
<!-- SECTION:DESCRIPTION:BEGIN -->
「変更されたファイルのみ表示」で、グローバルの gitignore が効かず `.DS_Store` などが untracked として出る。

原因: `BefoldApp/befold/App/GitLibrary.swift:53-56` の `disabledConfigLevels` が `GIT_CONFIG_LEVEL_SYSTEM` と `GIT_CONFIG_LEVEL_XDG` を含み、同 66-71 行の bootstrap が両レベルの検索パスを空文字にしている。同 47-52 行の doc コメントは「`GIT_CONFIG_LEVEL_GLOBAL`(~/.gitconfig) は core.excludesFile のため意図して無効化しない」と明記しており、グローバル ignore を効かせる意図はあるが、**XDG 配置(~/.config/git/)のケースが漏れている**。

XDG を潰すと 2 つ同時に壊れる。
1. `~/.config/git/config` に書いた `core.excludesFile` が読まれない
2. `core.excludesFile` 未設定時の既定フォールバックである `~/.config/git/ignore` も読まれない（libgit2 の attrcache は core.excludesfile が無いとき XDG の `ignore` を探すが、検索パスが空なので何も見つからない）

実測（このマシン、リポジトリルート）:
- `git config --global --get core.excludesFile` → 空（未設定）
- `git config --list --show-origin | grep core.` → `file:/Users/tokutomi/.config/git/config core.pager=delta`（グローバル config は XDG 配置）
- `git check-ignore -v --no-index .DS_Store` → `/Users/tokutomi/.config/git/ignore:3:.DS_Store`（除外は XDG の ignore が担っている）
- 作業ツリー直下に `.DS_Store` が実在

status オプション側は問題ない: `BefoldApp/befold/App/GitStatusReader.swift:135-158` は `INCLUDE_UNTRACKED | RENAMES_HEAD_TO_INDEX | RENAMES_INDEX_TO_WORKDIR` のみで `GIT_STATUS_OPT_INCLUDE_IGNORED` は立てていない。独自の ignore 実装も無く、判定は完全に libgit2 任せ。

TASK-462(dd8feeeb) は検索パス書き込みを bootstrap 一度きりに閉じた変更で GLOBAL は潰していない。XDG 無効化は TASK-435.1 の決定（「無効化するのは SYSTEM と XDG の 2 つ」）に由来し、それ以前から存在する。決定性を目的とした無効化だが、ignore 設定を巻き添えにしている点でこの決定の見直しが必要。

未確認:
- 実アプリを起動してサイドバーに `.DS_Store` が出ることの実測（ビルド・起動していない）
- libgit2 1.9.2 の attrcache の XDG フォールバック実装をソースで未確認（`attr_cache_lookup_path` / `GIT_IGNORE_FILE_XDG`）。修正前に実ソースで確認すること
<!-- SECTION:DESCRIPTION:END -->
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 XDG 配置(~/.config/git/config)の core.excludesFile が読まれ、対象ファイルがサイドバーに出ない
- [ ] #2 core.excludesFile 未設定で ~/.config/git/ignore のみがある環境でも除外が効く
- [ ] #3 config レベルを無効化する決定（SYSTEM/XDG）の見直し結果を doc コメントと Implementation Notes に記録した
- [ ] #4 一時 HOME/XDG_CONFIG_HOME を使った ignore 判定のユニットテストがあり、修正を戻すと落ちることを確認した
<!-- AC:END -->
