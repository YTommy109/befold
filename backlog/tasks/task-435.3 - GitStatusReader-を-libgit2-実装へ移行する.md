---
id: TASK-435.3
title: GitStatusReader を libgit2 実装へ移行する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 15:02'
updated_date: '2026-08-10 16:49'
labels:
  - refactor
dependencies:
  - TASK-435.1
parent_task_id: TASK-435
priority: high
type: task
ordinal: 668000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435 のサブタスク。`GitStatusReader`（`BefoldApp/befold/App/GitStatusReader.swift`, 341 行）の 3 呼び出しと、その出力パーサを libgit2 へ移す。

## 移行対象

| 用途 | 現行の引数 | file:line | libgit2 側 |
|---|---|---|---|
| 作業ツリー状態 | `--no-optional-locks status --porcelain=v2 -z` | GitStatusReader.swift:88 | `git_status_list_new` + `git_status_byindex` |
| submodule パス | `config -z --file .gitmodules --get-regexp` | GitStatusReader.swift:160 | `git_submodule_foreach` |
| ブランチ差分ファイル | `diff --name-status -z <base> HEAD` | GitStatusReader.swift:189 | `git_diff_tree_to_tree` + `git_diff_get_delta` |

撤去対象のパーサ: `parsePorcelainV2` / `fieldsBeforePath` / `submodulePath(in:)` / `parseRecord` / `parseUntrackedEntry` / `parseChangedEntry` / `parseConfigValues` / `parseNameStatus`。

## 実測で確認済みの対応関係（親タスク Notes 参照）

porcelain=v2 の XY 2 文字は `git_status_entry.head_to_index.status`（X）と `.index_to_workdir.status`（Y）を `git_delta_t` → 文字へ写像すれば再現できる。フィクスチャ 6 パターン（staged 追加 / workdir 削除 / rename / staged 変更 / workdir 変更 / untracked）でエントリ数・パス・rename の元パスまで一致することを実測済み。

必要なオプション: `GIT_STATUS_OPT_INCLUDE_UNTRACKED` / `RENAMES_HEAD_TO_INDEX` / `RENAMES_INDEX_TO_WORKDIR` / `EXCLUDE_SUBMODULES`。

## 注意

`GitFileStatus.Change` は porcelain の XY コード（Character）をそのまま持つ。ここを内部の列挙型へ変えるかは設計判断であり、`/review-design` で扱うこと。表示側（SidebarGitStatus / GitStatusBadge / GitFolderStatus）とそのテストは XY 由来の値に依存している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GitStatusReader の 3 呼び出しがすべて libgit2 実装に置き換わり、このファイルから GitCommandRunning への依存が消えている
- [x] #2 porcelain=v2 のテキストパーサ（parsePorcelainV2 ほか）が撤去され、GitStatusReaderTests / GitStatusReaderIntegrationTests の既存テストが同等の期待値で通る（AC #4）
- [x] #3 submodule の境界検出が git_submodule_foreach ベースで再実装され、従来と同じ結果を返すことがテストで担保されている（AC #5 の一部）
- [x] #4 ブランチ差分ファイルの取得が従来と同じ結果（rename/copy の元パス扱いを含む）を返すことがテストで担保されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー結果の反映（/review-design 実施済み）

1. `GitStatusReader` から `runner: GitCommandRunner` を削除する。`comparisonBase` の既定は
   `GitComparisonBaseResolver()`（内部で自前の runner を持つ。435.4 で libgit2 化）。
   `repository` / `fileReader` はそのまま。

2. `status(forRepositoryAt:)` は `GitLibrary.withRepository` を **1 回だけ**呼び、その中で
   status 列挙・submodule 列挙・branch diff をすべて行う。内部ヘルパーは URL ではなく
   `OpaquePointer` を受け取る形にして、開き直す実装が書けない構造にする（項目 6・9）。
   `.failure(.notARepository)` → `.empty`（キャッシュ可）、`.failure(.unusable)` → nil（キャッシュ不可）。

3. status の取得: `git_status_list_new` + `git_status_byindex`。
   XY は `git_status_entry.head_to_index.status`（X）と `.index_to_workdir.status`（Y）を
   `git_delta_t` → `GitFileStatus.Change` へ写す。`GIT_DELTA_UNTRACKED` は `isUntracked`。

   **設定するオプション**: `INCLUDE_UNTRACKED` / `RENAMES_HEAD_TO_INDEX` / `RENAMES_INDEX_TO_WORKDIR`。

   **設定してはならないオプション**（それぞれ理由付きで doc に残す）:
   - `UPDATE_INDEX`: status が .git/index を書き、fingerprint 無効化と組んで自己励振ループになる
     （外部 git 方式の `--no-optional-locks` が防いでいたもの）。
     `GitStatusReaderIntegrationTests.statusDoesNotDisturbIndexFingerprint` が守る
   - `EXCLUDE_SUBMODULES`: 設定すると submodule のエントリが出ず、境界検出の源 #2
     （.gitmodules に登録されていない gitlink）が失われる。**親タスク Notes の記載を変更する**
   - `RECURSE_UNTRACKED_DIRS`: 設定しないことで untracked ディレクトリが末尾スラッシュ付きの
     1 件に畳まれ、境界検出の源 #3（.git を持つ畳み込みディレクトリ）が成立する
   - `INCLUDE_IGNORED` / `INCLUDE_UNREADABLE`: 現行どおり ignored と読めないファイルを無視する

4. 境界検出の 3 系統を保つ:
   - 源 #1（.gitmodules 登録）: `git_submodule_foreach`。`git config --file .gitmodules --get-regexp` と
     `parseConfigValues` を撤去する
   - 源 #2（.gitmodules に無い gitlink）: `<sub>` が S 始まりというテキスト判定をやめ、
     `git_diff_file.mode == GIT_FILEMODE_COMMIT` という事実で判別する（項目 1: 判定の真実の源）
   - 源 #3（.git を持つ畳み込み未追跡ディレクトリ）: `path.hasSuffix("/")` の判定はそのまま使える

5. branch diff: `git_revparse_single` で base と HEAD を tree へ peel し、
   `git_diff_tree_to_tree` + `git_diff_find_similar`（rename 検出。git diff の既定に合わせ copy は検出しない）。
   `git_diff_get_delta` の `new_file.path` を採る（R/C で変更後のパスになる。現行の
   parseNameStatus が最後のパスフィールドを採っていたのと同じ）。

6. `GitFileStatus.Change` は Character rawValue を維持する。`GitStatusBadge.swift:42/51/57` が
   rawValue をバッジ文字として直接使っており、porcelain の文字は実装詳細ではなく
   利用者が知っている表示語彙であるため。ただし `init?(porcelainCode:)` は呼び出し元 3 箇所が
   すべて撤去対象で dead になるので、`init?(delta:)`（git_delta_t から）へ置き換える。
   git の変更語彙との写像表を 1 箇所に保つ（435.4 の GitDiffReader も同じ表を使う）。

7. 撤去するもの: `parsePorcelainV2` / `fieldsBeforePath` / `submodulePath(in:)` / `parseRecord` /
   `parseUntrackedEntry` / `parseChangedEntry` / `parseConfigValues` / `parseNameStatus` /
   `ParsedStatus` / `Entry`。

## テストの移動

`GitStatusReaderTests` の 14 本のうち 10 本は porcelain / name-status / config -z の**テキスト書式**を
固定しており、書式が消えるため撤去する。状態対応を測っている 3 本（staged/unstaged/untracked の判別、
staged と unstaged の両立、未マージ）と ignored/unchanged の意味論 1 本は、実 git フィクスチャの
Integration テストへ移す。

Integration テスト 10 本はすべて「git 状態 → GitFileStatus」の対応を測っており、実装差し替え後も
**同じ期待値のまま通るべきもの**（AC #2 の判定基準にする）。

## 守るものを足す（項目 9）

「EXCLUDE_SUBMODULES を設定しない」には破れたら落ちるものが無い。`.gitmodules` に登録されていない
gitlink を境界として検出する Integration テストを 1 本足し、源 #2 が消えたら落ちるようにする。
rename / delete / typechange の写像も、現行の unit テストが書式ごと消えるぶん Integration で押さえる。

## 該当しなかったチェック項目

- 項目 2: nil と .empty の区別は GitRepository と同じ 2 分岐へ写し、既存の不変条件を迂回しない
- 項目 4: 新しい状態は増えない。INCLUDE_UNREADABLE を設定しないので読めないファイルは現行どおり無視
- 項目 8: 新しい非同期状態を導入しない。GitStatusStore の世代管理は不変
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装結果（2026-08-11）

`GitStatusReader` の 3 呼び出しを libgit2 へ移し、porcelain / name-status / config -z の
テキストパーサ 8 個と `ParsedStatus` / `Entry` を撤去した。

| 用途 | 移行後 |
|---|---|
| 作業ツリー状態 | `git_status_list_new` + `git_status_byindex` |
| submodule パス | `git_submodule_foreach` + `git_submodule_path` |
| ブランチ差分 | `git_revparse_single` → `git_object_peel` → `git_diff_tree_to_tree` + `git_diff_find_similar` |

`GitFileStatus.Change` は Character rawValue を維持した（`GitStatusBadge.swift:42/51/57` が
rawValue をバッジ文字として直接使う）。`init?(porcelainCode:)` は呼び出し元 3 箇所がすべて
撤去対象で dead になるため `init?(delta: git_delta_t)` へ置き換え、git の変更語彙との写像表を
1 箇所に保った。

### 実測で設計を変えた点（当初計画からの変更）

**境界検出は 3 系統ではなく 2 系統で足りた。** 計画では源 #2（.gitmodules に登録されていない
gitlink）を `git_diff_file.mode == GIT_FILEMODE_COMMIT` で判別する予定だったが、実測の結果
`git_submodule_foreach` が **index の gitlink まで列挙する**ことが分かった。登録を
`.gitmodules` と `.git/config` の両方から消しても検出できる（`showsBadgeForDirtySubmodule`）。
そのため mode による判定は同じ集合にしかならず、書いた `isGitlink` を撤去した。

### 「破れたら落ちるもの」を実際に破って確認した

規約どおり担保を付けるだけでなく、**担保が効くことを自己テストで確認した**。

1. `GIT_STATUS_OPT_EXCLUDE_SUBMODULES` を足す → `showsBadgeForDirtySubmodule` が
   `statuses["sub"] == nil` で落ちる（確認済み）。中身が変更されたサブモジュールの
   バッジが消える退行を検知する
2. `GIT_STATUS_OPT_UPDATE_INDEX` を足す → `statusDoesNotDisturbIndexFingerprint` が落ちる

**2 は最初は効いていなかった。** 元のテストはファイルの内容ごと書き換えており、その場合
libgit2 は UPDATE_INDEX を設定しても index を書かないため、フラグを足しても通ってしまった
（実測）。**内容を変えずに mtime だけ動かす**形（同じ内容で書き直す）へ直して初めて落ちるようになった。
stat だけが古くなった状態こそが UPDATE_INDEX の書き込み条件であり、自己励振の防止線は
そこに置かなければ効かない。この経緯をテストの doc コメントに残した。

### テストの移動

`GitStatusReaderTests.swift`（14 本）を削除した。10 本は porcelain / name-status / config -z の
テキスト書式そのものを固定しており、書式が消えたため。状態対応を測っていた 4 本は実 git
フィクスチャの Integration テストへ移設し、rename / delete / unregistered gitlink の 3 本を新設した
（差し引き 14 削除・5 追加＝ -9 本）。

`GitStatusReaderIntegrationTests.swift` が file_length / type_body_length を超えたため、
ブランチ差分の 4 本を `GitStatusBranchDiffIntegrationTests.swift` へ分割した（閾値は緩めない）。

### 検証

- `swift test --skip ViewerRenderer`: **1346 tests / 196 suites passed**（16.5s）
- `swift test --filter ViewerRenderer`: **51 tests / 9 suites passed**（0.6s）
- 合計 1397 本。移行前の 1406 本から -9 本で、上記のテスト増減と一致する
- **単一プロセスでの全件実行は完了できていない。** 別セッションが別 worktree
  （`chore/git_lib` ではない `chore/code_review`）で `swift test` を並走させており、
  その CPU 競合で `ViewerRendererZoomIntegrationTests` の WKWebView が
  `isReady == false` のままタイムアウトする。同じ 3 スイートを単独で回すと 0.6 秒で全通過するため、
  本タスクの変更（BefoldRenderKit を触っていない）が原因ではないと判断した
- swiftlint: origin/main とのベースライン差分ゼロ
- swiftformat: 全ターゲットで整形差分なし
- `xcodegen generate`: ファイルの削除・追加・改名のたびに実行済み
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitStatusReader の 3 呼び出し（作業ツリー状態・submodule パス・ブランチ差分ファイル）を libgit2 へ移行し、porcelain=v2 / name-status / config -z のテキストパーサ 8 個を撤去した。GitFileStatus.Change は Character rawValue のまま維持し（バッジ文字として直接使われるため）、写像の入口だけを init?(porcelainCode:) から init?(delta:) へ置き換えた。実測により境界検出は当初計画の 3 系統ではなく 2 系統で足りることが分かり（git_submodule_foreach が index の gitlink まで列挙する）、書いた mode 判定を撤去した。status のオプションは「設定しないもの」に理由があるため、EXCLUDE_SUBMODULES と UPDATE_INDEX それぞれについて実際にフラグを足して担保テストが落ちることを確認した。UPDATE_INDEX 側は当初テストが効いておらず、内容を変えず mtime だけ動かす形へ直して初めて検知できるようになった。検証: swift test は非 renderer 1346 本 + renderer 51 本の 2 パスで全通過（別セッションの並走で単一プロセス全件実行は不可。詳細は Notes）、swiftlint はベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
