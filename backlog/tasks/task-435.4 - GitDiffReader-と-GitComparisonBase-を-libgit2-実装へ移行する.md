---
id: TASK-435.4
title: GitDiffReader と GitComparisonBase を libgit2 実装へ移行する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 15:03'
updated_date: '2026-08-10 17:11'
labels:
  - refactor
dependencies:
  - TASK-435.1
parent_task_id: TASK-435
priority: high
type: task
ordinal: 669000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435 のサブタスク。差分本体の生成と比較起点の解決を libgit2 へ移す。

## 移行対象

| 用途 | 現行の引数 | file:line | libgit2 側 |
|---|---|---|---|
| 差分本体 | `diff --no-color --no-ext-diff -U1000000 <base> -- <path>` | GitDiffReader.swift:55 | `git_diff_tree_to_workdir_with_index`（`context_lines = 1_000_000`, pathspec 1 件）+ `git_diff_to_buf(GIT_DIFF_FORMAT_PATCH)` |
| 管理外/コミット無しの切り分け | `rev-parse --git-dir` | GitDiffReader.swift:73 | リポジトリを開けたか + `git_repository_head_unborn` |
| 未追跡判定 | `ls-files --error-unmatch -z -- <path>` | GitDiffReader.swift:91 | `git_index_get_bypath` |
| 比較起点 | `merge-base HEAD <default>` | GitComparisonBase.swift:37 | `git_merge_base` |
| 既定ブランチ探索 | `rev-parse --verify --quiet main` / `master` | GitComparisonBase.swift:53 | `git_branch_lookup(GIT_BRANCH_LOCAL)` |
| origin の既定ブランチ | `symbolic-ref --short refs/remotes/origin/HEAD` | GitComparisonBase.swift:62 | `git_reference_lookup` + `git_reference_symbolic_target` |

## 実測で確認済み（親タスク Notes 参照）

`context_lines = 1_000_000` + `git_diff_to_buf` の出力が `git diff --no-color --no-ext-diff -U1000000` と**バイト単位で一致**した。したがって viewer.js の `parseUnifiedDiff` は無改修で足りる見込み。

## 注意

`GitDiffReader.isBinaryDiff` は git の固定文言（`Binary files ` / `GIT binary patch`）を行頭一致で見ている。libgit2 側では `git_diff_delta.flags` の `GIT_DIFF_FLAG_BINARY` で判定できるため、文字列一致をやめる余地がある（`/review-design` で扱う）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GitDiffReader / GitComparisonBaseResolver の 6 呼び出しがすべて libgit2 実装に置き換わり、両ファイルから GitCommandRunning への依存が消えている
- [x] #2 -U1000000 相当の全文コンテキスト diff が再現され、viewer.js の parseUnifiedDiff が無改修で従来どおり描画できる（AC #3）
- [x] #3 GitDiffReaderIntegrationTests の既存テストが同等の期待値で通る（バイナリ判定・未追跡・コミット無し・管理外の切り分けを含む）
- [x] #4 比較起点の解決（merge-base / 既定ブランチ探索 / origin の既定ブランチ）が従来と同じ結果を返すことがテストで担保されている（AC #5 の一部）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー結果の反映（/review-design 実施済み）

1. `GitDiffReader` / `GitComparisonBaseResolver` から `runner: GitCommandRunner` を削除する。
   `GitComparisonBaseResolving.comparisonBase(forRepositoryAt:) -> String?` の**シグネチャは変えない**。
   返す文字列はコミット ID（`git_oid` の hex）で、`GitStatusReader` 側は
   `git_revparse_single` に食わせている（兄弟の消費経路。ここを変えると両方が壊れる）。

2. `GitComparisonBaseResolver`:
   - `merge-base HEAD <default>` → `git_merge_base` + `git_oid_tostr`
   - `rev-parse --verify --quiet main/master` → `git_branch_lookup(GIT_BRANCH_LOCAL)`
   - `symbolic-ref --short refs/remotes/origin/HEAD` → `git_reference_lookup` +
     `git_reference_symbolic_target`（`refs/remotes/origin/main` → `origin/main` へ短縮）
   - 解決の順序（origin/HEAD → main → master → nil）は変えない

3. `GitDiffReader`:
   - 差分本体 → `git_diff_tree_to_workdir_with_index`（base の tree と作業ツリー）。
     `context_lines = 1_000_000`、pathspec に**ルート相対パス 1 件**（libgit2 の pathspec は
     絶対パスを受けない。現行は `url.path` の絶対パスを git に渡していた）
   - 出力 → `git_diff_to_buf(GIT_DIFF_FORMAT_PATCH)`
   - 管理外/コミット無しの切り分け → リポジトリを開けたか（`.notARepository` → `.notInRepository`、
     `.unusable` → nil）と `git_repository_head_unborn`（→ `.noCommits`）
   - 未追跡判定 → `git_index_get_bypath`

4. **`isBinaryDiff` の文字列一致をやめる**（項目 1: 判定の真実の源）。
   現行は `Binary files ` / `GIT binary patch` という git の固定英文を行頭一致で見ている。
   libgit2 では `git_diff_delta.flags` の `GIT_DIFF_FLAG_BINARY` という事実で判定できる。
   文言はロケールや版で変わりうるうえ、差分本文にその文字列を含むテキストファイルが
   あれば誤検知する（同じ形の誤検知が TASK-316 で実際に起きている）。

5. **`GIT_DIFF_UPDATE_INDEX` を設定しない**（項目 5）。status 側と同じ理由で、diff が
   `.git/index` の stat キャッシュを書き戻すと監視側と自己励振ループになる
   （外部 git 方式の `--no-optional-locks` が防いでいたもの）。
   **TASK-435.3 と同じ形の担保テストを diff 側にも置く**（内容を変えず mtime だけ動かし、
   diff 実行の前後で indexFingerprint が変わらないこと）。435.3 の実測で、内容ごと
   書き換える形のテストではこのフラグの退行を検知できないことが分かっている。

6. 保つ不変条件（項目 2）:
   - 起点は必ず `GitComparisonBaseResolving` から採り、**分からないときだけ** HEAD へ落とす
     （差分が空だったから落とす、ではない）
   - 空の出力は「差分なし」ではない。追跡されているかで `.noChanges` / `.untracked` を分ける
   - nil は「不明」でキャッシュ不可、`.notInRepository` は確定でキャッシュ可

## 守るものを足す（項目 7・9）

AC #2 は「viewer.js の parseUnifiedDiff が無改修で動く」ことだが、それを直接測るテストは無い。
**libgit2 の出力と実 `git diff --no-color --no-ext-diff -U1000000 <base> -- <path>` の出力を
突き合わせる Integration テスト**を置く。守りたいもの（git と同じ unified diff テキスト）と
測るもの（実 git の出力との一致）を揃える。

## 受け入れたコスト（項目 6）

差分 1 回につきリポジトリを 2 回開く（比較起点の解決 + 差分本体）。起点の解決を
`GitComparisonBaseResolving` の seam の外へ出せば 1 回にできるが、その seam は
「バッジと差分が同じ起点を使う」ことの唯一の担保であり（TASK-352）、性能のために壊さない。
open は 0.263ms（TASK-435.1 実測）で、置き換える subprocess は 67ms。

## 該当しなかったチェック項目

- 項目 3: `GitFileDiff` のケースは増減しない。`comparisonBase` のシグネチャも変えないため
  兄弟の消費経路（GitStatusReader）は無改修
- 項目 4: 新しい表示状態は増えない
- 項目 8: 非同期の世代管理は `GitDiffLoader` 側にあり、本タスクでは触らない
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装結果（2026-08-11）

`GitDiffReader` と `GitComparisonBaseResolver` の 6 呼び出しを libgit2 へ移し、両ファイルから
`GitCommandRunning` への依存を消した。**これでプロダクトコードから `GitCommandRunner` の
呼び出し元が 0 になった**（残るのは `GitCommandRunner.swift` 自身と 3 箇所の doc コメントのみ。
撤去は TASK-435.5）。

| 用途 | 移行後 |
|---|---|
| 差分本体 | `git_diff_tree_to_workdir_with_index`（context_lines = 1_000_000, pathspec 1 件）+ `git_diff_to_buf` |
| 管理外/コミット無し | リポジトリを開けたか + `git_repository_head_unborn` |
| 未追跡判定 | `git_index_get_bypath` |
| 比較起点 | `git_merge_base` + `git_oid_tostr` |
| 既定ブランチ探索 | `git_branch_lookup(GIT_BRANCH_LOCAL)` |
| origin の既定ブランチ | `git_reference_lookup` + `git_reference_symbolic_target` |

`GitComparisonBaseResolving.comparisonBase(forRepositoryAt:) -> String?` のシグネチャは
変えていない。返すコミット ID は `GitStatusReader` 側が `git_revparse_single` に食わせており、
ここを変えると兄弟の消費経路が壊れる。

### 実測で分かったこと

**1. `GIT_DIFF_FLAG_BINARY` は patch を生成した後でなければ立たない。**
当初は `git_diff_to_buf` の前に `git_diff_get_delta` の flags を見ていたが、バイナリファイルでも
フラグが立たず `.diff("...Binary files ... differ")` が返った。フラグは中身を読んで初めて確定するため、
判定を patch 生成後へ移した。この順序依存を doc コメントに残した。

**2. `git_strarray` が指す配列は差分生成の呼び出しより長生きさせる必要がある。**
オプションを組み立てて返す `makeOptions` の形にしたところ、Swift が
`argument 'strings' must be a pointer that outlives the call` を警告した（動いてはいたが未定義動作）。
pathspec の組み立てと `git_diff_tree_to_workdir_with_index` を同じスコープへ閉じて解消した。

**3. libgit2 の pathspec は絶対パスを受けない。** 外部 git 方式は `url.path` の絶対パスを
そのまま渡していたため、ルート相対パスへ変換する処理を足した。

### 判定の真実の源を移した点

`isBinaryDiff` の文字列一致（`Binary files ` / `GIT binary patch` の行頭一致）を撤去し、
`git_diff_delta.flags` の `GIT_DIFF_FLAG_BINARY` による判定へ移した。
これに伴い書式を固定していた unit テスト 2 本を削除し、実 git フィクスチャの
Integration テスト 2 本へ置き換えた（NUL を含むファイル / 本文に `Binary files … differ` を
含むテキストファイル）。後者は文字列一致へ戻すと落ちる。

### 「破れたら落ちるもの」を実際に破って確認した

- `GIT_DIFF_UPDATE_INDEX` を足す → `diffDoesNotDisturbIndexFingerprint` が落ちる（確認済み）。
  TASK-435.3 の実測に従い、内容を変えず mtime だけ動かす形にしてある
- `matchesRealGitUnifiedDiffOutput`: libgit2 の出力と実 git の
  `--no-color --no-ext-diff -U1000000 <base> -- <path>` の出力が**文字列として完全一致**することを
  実測で確認した（AC #2 の担保。viewer.js の parseUnifiedDiff を直接測る手段が無いため、
  守りたいもの＝git と同じ unified diff テキストを、実 git の出力との一致で測る）

### 検証

- `swift test --skip ViewerRenderer`: **1348 tests / 196 suites passed**
- `swift test --filter ViewerRenderer`: **51 tests / 9 suites passed**
- 合計 1399 本（435.3 終了時の 1397 本 + バイナリ判定 2 本の入れ替え + 担保 2 本 = +2）
- 単一プロセスでの全件実行は TASK-435.3 と同じ理由で完了できていない。別セッションが
  別 worktree で `swift test` を並走させており、CPU 競合で
  `ViewerRendererZoomIntegrationTests` の WKWebView が `isReady == false` のままになる。
  同スイートを単独で回すと 0.6 秒で全通過する
- swiftlint: origin/main とのベースライン差分ゼロ
- swiftformat: 全 9 ターゲットで整形差分なし
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitDiffReader と GitComparisonBaseResolver の 6 呼び出しを libgit2 へ移行し、両ファイルから GitCommandRunning への依存を消した。これでプロダクトコードから GitCommandRunner の呼び出し元が 0 になった（撤去は TASK-435.5）。isBinaryDiff の文字列一致（git の固定英文の行頭一致）は GIT_DIFF_FLAG_BINARY による判定へ移し、本文に「Binary files … differ」を含むテキストファイルの誤判定が構造的に起きない形にした。AC #2 は、libgit2 の出力が実 git の --no-color --no-ext-diff -U1000000 の出力と文字列として完全一致することを Integration テストで固定して担保した。実測で 3 点の落とし穴を潰した: GIT_DIFF_FLAG_BINARY は patch 生成後でなければ立たない、git_strarray が指す配列は差分生成より長生きさせる必要がある（Swift が未定義動作を警告）、libgit2 の pathspec は絶対パスを受けない。検証: 非 renderer 1348 本 + renderer 51 本が全通過、swiftlint はベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
