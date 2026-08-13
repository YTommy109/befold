---
id: TASK-467
title: XDG 配置のグローバル gitignore が読まれず、無視すべきファイルが「変更されたファイルのみ表示」に出る
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-13 04:30'
updated_date: '2026-08-13 05:50'
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

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 XDG 配置(~/.config/git/config)の core.excludesFile が読まれ、対象ファイルがサイドバーに出ない
- [x] #2 core.excludesFile 未設定で ~/.config/git/ignore のみがある環境でも除外が効く
- [x] #3 config レベルを無効化する決定（SYSTEM/XDG）の見直し結果を doc コメントと Implementation Notes に記録した
- [x] #4 XDG の config 検索パスが空にされず既定のまま生きていることを観測するテストがあり、XDG を無効化リストへ戻すと落ちる
- [x] #5 core.excludesFile による除外が実際に効くことを、プロセスグローバルを触らずに固定する統合テストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー（/review-design）の結論

方針: 新しい機構を足さず、GitLibrary.disabledConfigLevels から GIT_CONFIG_LEVEL_XDG を外して
[GIT_CONFIG_LEVEL_SYSTEM] だけにする。これで XDG の config と ignore の両経路が同時に戻る。

1. GitLibrary.swift: disabledConfigLevels を [GIT_CONFIG_LEVEL_SYSTEM] にし、doc コメントへ
   決定の見直し結果（SYSTEM だけを無効化する理由 / XDG を無効化しない理由）を書く
2. GitLibraryTests: disablesSystemAndXdgConfigSearchPaths を書き換える。count 比較ではなく
   配列そのものを比較し、XDG が無効化リストへ戻ったら落ちるようにする
3. XDG の検索パスが既定（$XDG_CONFIG_HOME/git または ~/.config/git）のまま生きていることを
   直接観測するテストを足す
4. core.excludesFile 経由の除外が実際に効くことを、リポジトリ内 config を使った
   統合テストで固定する（プロセスグローバルを触らずに済む経路）
5. 修正を戻して落ちることを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 設計レビュー（実装着手前, /review-design）

### 項目 7（測るものと守るものの一致）— AC #4 は現状の記述では実現できない

AC #4 は「一時 HOME/XDG_CONFIG_HOME を使った ignore 判定のユニットテスト」を求めているが、
これは 2 つの理由で成立しない。

1. **env の差し替えが効かない（実測: libgit2 1.9.2 のソース）。**
   `src/libgit2/sysdir.c:452-459` の `git_sysdir_global_init()` が `git_libgit2_init()` の中で
   全レベルの検索パスを**先読みで** guess する。XDG の guess（同 375-402）が
   `XDG_CONFIG_HOME` / `HOME` を読むのは**この 1 回だけ**で、以降に env を変えても
   キャッシュ済みの `git_sysdir__dirs` は変わらない。テストから env を変えても観測できない。
2. **init 前に env を差し替える形も、post-init に検索パスを書く形も既存の不変条件に反する。**
   前者は bootstrap がプロセス一度きりのため、並行実行される Swift Testing で実行順に依存する。
   後者は `GitLibraryTests.searchPathIsWrittenOnlyByGitLibrary` が禁じており、TASK-462 で
   実際に thread-sanitizer が 5 本連続で data race を報告した経路そのもの。
   `GitLibraryTests.swift:41-48` にも「偽ホームを置く形にはしない」と理由付きで記録がある。

したがって AC #4 を「プロセスグローバルを触らずに、修正が戻ったら落ちる形で担保する」へ
書き換えた。担保は次の 2 本に分ける。

- XDG の検索パスが空にされず既定のまま生きていること（壊れた不変条件そのものの観測）
- `core.excludesFile` 経由の除外が実際に効くこと（リポジトリ内 config を使い、
  プロセスグローバルを一切触らない統合テスト）

### 項目 3（消費経路の全列挙）

`disabledConfigLevels` の読み手は 3 箇所のみ（`GitLibrary.swift:71` の bootstrap、
`GitLibraryTests.swift:54,65`）。`configSearchPath` の読み手はテストのみ。漏れなし。

### 項目 9（決めた粒度を守らせるもの）

既存テストは `disabledConfigLevels.count == 2` という**個数**で見ており、
中身が入れ替わっても通ってしまう。配列そのものの比較へ変える。

### 項目 1（判定の真実の源）/ 項目 2（既存の不変条件との衝突）

判定は「レベルの列挙」であってデータの中身ではない。該当なし。
「検索パスを書くのは bootstrap だけ」の不変条件は、リストを短くするだけなので保たれる。
弱まるのは決定性の不変条件だが、`~/.gitconfig`（GLOBAL）を既に有効にしている以上、
同じユーザーの設定が置き場所（`~/.gitconfig` か `~/.config/git/config` か）で
扱いが変わるほうが一貫しない。無効化を「マシン全体（SYSTEM）だけ」へ縮めるのが筋。

### 項目 4 / 5 / 6 / 8 / 10

- 項目 4: 新しいユーザー可視状態は増えない（除外が効くようになるだけ）。
- 項目 5: 書き込みを増やさずリストを短くするだけで、初期化の順序は変わらない。
- 項目 6: config 読み取りは既にリポジトリを開くたびに走っており、頻度は変わらない。
- 項目 8: 非同期で置き換わる表示状態を足さない。
- 項目 10: 型グループは `BefoldApp/befold/App/GitLibrary` = 113 行（実測）。
  増分は doc コメントと配列 1 行のみで、責務は増えない。

## 実装

`GitLibrary.disabledConfigLevels` を `[GIT_CONFIG_LEVEL_SYSTEM]` へ縮めた。新しい機構は足していない
（XDG の検索パスを空文字で潰すのをやめるだけで、libgit2 の既定 guess がそのまま生きる）。

doc コメントへ決定の見直しを記録した: 無効化するのは**マシン全体の設定（SYSTEM）だけ**で、
ユーザー自身の設定は置き場所（`~/.gitconfig` か `~/.config/git/` か）に関わらず無効化しない。
片方だけ読むと、同じ設定が置き場所によって効いたり効かなかったりするため。

## 実測（causality の確認）

一時的なプローブテストで、実ワークツリー（`.DS_Store` が実在、`core.excludesFile` は未設定で
除外は `~/.config/git/ignore` が担当）に対し `GitStatusReader.status(forRepositoryAt:)` を実行した。

- 修正後: `xdg-search-path=/Users/tokutomi/.config/git` / `.DS_Store` は status に**出ない**（9 件）
- XDG を無効化リストへ戻すと: `xdg-search-path=`（空）/ `.DS_Store` が**出る**（10 件）

プローブは実測のためのもので、実マシンの `~/.config/git` に依存するためコミットしていない。

## テスト

- `GitLibraryTests.disablesOnlySystemConfigSearchPath`: 個数比較をやめ、配列そのものを比較する。
  XDG を戻すと落ちる（実測済み）。
- `GitLibraryTests.keepsUserConfigSearchPathsEnabled`: GLOBAL に加え XDG も無効化リストに無いこと、
  かつ XDG の検索パスが既定（`$XDG_CONFIG_HOME/git` または `~/.config/git`）と一致することを見る。
  XDG を戻すと `"" != "/Users/tokutomi/.config/git"` で落ちる（実測済み）。
- `GitStatusReaderIntegrationTests.honorsCoreExcludesFile`: `core.excludesFile` を読んだら実際に
  除外へ効くことを、リポジトリ内 config だけで固定する（プロセスグローバルを触らない）。
  これは修正を戻しても落ちない**別半分**の担保であり、意図的にそうしている（理由はテストの
  doc コメントに記載）。「その config レベルを読むか」は上の 2 本が検索パスの側で見る。

## 検証

`swift test` 全体 1472 件成功。swiftformat 差分なし。swiftlint は 54 件（main と同水準）で、
変更した 3 ファイルに指摘なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitLibrary.disabledConfigLevels から GIT_CONFIG_LEVEL_XDG を外し、無効化をマシン全体の設定（SYSTEM）だけに縮めた。これで ~/.config/git/config の core.excludesFile と、その未設定時の既定フォールバックである ~/.config/git/ignore の両方が読まれるようになる。実測: 実ワークツリーに対する GitStatusReader の結果から .DS_Store が消えた（修正前 10 件 → 修正後 9 件、XDG を戻すと再び出ることも確認）。担保は GitLibraryTests の 2 本（無効化リストと XDG 検索パスの観測。修正を戻すと落ちることを確認済み）と、GitStatusReaderIntegrationTests.honorsCoreExcludesFile（core.excludesFile が除外へ効くことをプロセスグローバル非依存で固定）。swift test 1472 件成功。
<!-- SECTION:FINAL_SUMMARY:END -->
