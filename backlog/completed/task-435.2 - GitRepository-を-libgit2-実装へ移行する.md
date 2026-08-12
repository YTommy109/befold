---
id: TASK-435.2
title: GitRepository を libgit2 実装へ移行する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 15:02'
updated_date: '2026-08-10 15:55'
labels:
  - refactor
dependencies:
  - TASK-435.1
parent_task_id: TASK-435
priority: high
type: task
ordinal: 667000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435 のサブタスク。`GitRepository`（`BefoldApp/befold/App/GitRepository.swift`）の 4 呼び出しを libgit2 へ移す。

## 移行対象

| 用途 | 現行の引数 | file:line | libgit2 側 |
|---|---|---|---|
| リポジトリルート解決 | `rev-parse --show-toplevel` | GitRepository.swift:82 | `git_repository_open_ext` + `git_repository_workdir` |
| 追跡ファイル一覧 | `ls-files -z` | GitRepository.swift:97 | `git_repository_index` + `git_index_get_byindex` の走査 |
| worktree 判定 | `rev-parse --git-common-dir --git-dir` | GitRepository.swift:125 | `git_repository_path` / `git_repository_commondir` / `git_repository_is_worktree` |
| worktree 列挙 | `worktree list --porcelain` | GitRepository.swift:144 | `git_worktree_list` + `git_worktree_lookup` + `git_worktree_path` |

## 実測で判明している差分（親タスク Notes 参照）

1. `git_worktree_list` は**リンク worktree だけ**を返し、メイン worktree を含まない。現行の `git worktree list --porcelain` はメインも含むため、メイン側は `git_repository_commondir` から自前で補う。
2. `git_worktree_*` はブランチ名を返さない。`GitWorktree` がブランチ名を持つため、各 worktree を開いて HEAD を読む手当てが要る。
3. index 走査は submodule の gitlink（例 `vendor/sub`）も含む。`git ls-files` と同じ挙動。

## 既存の縮退規約を保つこと

`GitRootLookup` の `.root` / `.notARepository`（確定・キャッシュ可）/ `.undetermined`（不明・キャッシュ不可）の 3 値の意味を変えない。libgit2 では「リポジトリでないことが確定した」と「開けなかった（未知の extensions・権限不足）」の区別が必要で、後者は `.undetermined` 側へ落とす。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GitRepository の 4 呼び出しがすべて libgit2 実装に置き換わり、このファイルから GitCommandRunning への依存が消えている
- [x] #2 GitRepositoryIntegrationTests / GitRepositoryTests の既存テストが同等の期待値で通る
- [x] #3 worktree 列挙がメイン worktree を含み、各エントリのブランチ名が従来と同じ結果を返すことがテストで担保されている
- [x] #4 リポジトリでないことが確定した場合と開けなかった場合が区別され、それぞれ .notARepository / .undetermined へ写像されることがテストで担保されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー結果の反映（/review-design 実施済み）

1. `GitRepository` から `runner: any GitCommandRunning` を削除する。`fileReader` は残す
   （`indexFingerprint` / `indexURL` / `gitDirectory` の 3 用途）。呼び出し側は
   `GitStatusReaderIntegrationTests` / `SidebarChangedFilesOnlyIntegrationTests` /
   `GitDiffReaderIntegrationTests` の `GitRepository(runner:)` を `GitRepository()` へ（3 箇所）。

2. `root(forFileAt:)`: `GitLibrary.withRepository` + `git_repository_workdir`。
   workdir が nil（bare）は `.notARepository`、`.failure(.notARepository)` は `.notARepository`、
   `.failure(.unusable)` は `.undetermined`。3 値の意味は変えない（AC #4）。

3. `trackedFiles(at:)`: `git_repository_index` + `git_index_get_byindex` の走査。
   開けない場合も index を読めない場合も nil（追跡 0 件と区別する既存規約どおり）。
   index から生バイトで取るため `core.quotepath` のエスケープ問題は原理的に無い。

4. `repositoryIdentity(forRoot:)`: `git_repository_is_worktree` で判定する
   （現行の `--git-common-dir` と `--git-dir` の文字列比較をやめる）。本体ルートは commondir の親。

5. `worktrees(forRoot:)`: 本体を commondir から合成し、`git_worktree_list` +
   `git_worktree_lookup` + `git_worktree_path` でリンク worktree を足す。ブランチ名は
   `git_worktree_*` から取れないため、各 worktree を開いて
   `git_repository_head_detached` + `git_repository_head` + `git_reference_shorthand` で読む。

### 設計レビューで方針を変えた点

- **`isMain` を配列位置から事実へ移す**（項目 1）。現行は `isMain: result.isEmpty`
  （GitRepository.swift:163）＝ git の出力順への暗黙依存。libgit2 では本体を commondir から
  自前で合成するので「commondir 由来の本体ルートか」という事実で決める。AC #3 のテストで
  「本体のみ isMain == true」と「本体が先頭」を別々に固定する。
- **`worktrees()` のリポジトリオープンを 2+N から 1+N へ**（項目 6）。起動時に
  `recentRepositoriesStore.entries()` の mainRoot 全件をループする（AppDelegate.swift:188-192）
  ため、1 回あたりの増加が件数倍で効く。root が worktree でなければ開き直さない。
- **libgit2 が返す全パスに `.standardizedFileURL` を通す**（項目 1）。mainRoot / worktree root は
  `RecentRepositoryEntry` として UserDefaults に永続化される。比較は全て
  `normalizedPathKey`（resolvingSymlinksInPath）を通るため衝突はしないが、表記を現行に揃える。
- **`indexFingerprint` / `indexURL` は libgit2 に寄せない**（項目 6）。GitStatusReader.swift:81 は
  サイドバーの .git 監視コールバックごと、GitCommandFileIndex.swift:66 は参照解決ごとに
  毎回生で走る門番であり、ここを libgit2 に寄せると監視イベント頻度 × ウィンドウ数で
  リポジトリオープンが増える。理由を doc コメントに残す。

### テストの移動（論点 B）

`static func parseWorktreeList(_:)` が消えるため、インメモリの網羅テスト 8 ケースが消える。
worktree 列挙の検証は実 git フィクスチャの Integration テストへ移す（本体含有・ブランチ短縮・
detached・3 件以上・並び順）。「worktree 行なし」「空パス」「空 branch」はテキスト形式固有の
入力なので対応する概念が無くなる。

縮退テストの注入点 `UnavailableGitCommandRunner` も使えなくなるため、
`GitLibraryTests.makeUnopenableRepository`（実 git を起動せず `.git/` を手で組む）へ置き換える。

### 該当しなかったチェック項目

- 項目 2: `.unusable → .undetermined` の写像を GitRepository 側で行うため、
  GitCommandFileIndex.swift:107 の「不明は覚えない」規約は保たれる。
- 項目 4: 新しい状態は増えない。branch を取れない worktree は displayName が
  ディレクトリ名に落ち、既存の detached と同じ表示になる。
- 項目 5: GitLibrary.bootstrap は static let の一度きり初期化で、withRepository 以外に
  リポジトリを開く経路が swiftlint（.swiftlint.yml:80-87）で塞がれている。
- 項目 8: 新しい非同期状態を導入しない。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装結果（2026-08-11）

`GitRepository` の 4 呼び出しを libgit2 へ移した。`runner: any GitCommandRunning` を削除し、
`fileReader` のみを残した（`indexFingerprint` / `indexURL` / `gitDirectory` の 3 用途）。

| 用途 | 移行後 |
|---|---|
| ルート解決 | `GitLibrary.withRepository` + `git_repository_workdir` |
| 追跡ファイル一覧 | `git_repository_index` + `git_index_get_byindex` の走査 |
| worktree 判定 | `git_repository_is_worktree`（文字列比較をやめた） |
| worktree 列挙 | 本体を `git_repository_commondir` から合成 + `git_worktree_list` / `_lookup` / `_path` |

### 設計レビュー（/review-design）で方針を変えた点

- `isMain` の決め方を配列位置（`result.isEmpty`）から出自（共通 gitdir 由来の本体か）へ移した。
  `git worktree list` の出力順への暗黙依存が消えた。Integration テストで「本体が先頭」と
  「isMain が本体のみ true」を別々の `#expect` で固定し、片方だけ壊れても落ちるようにした。
- `worktrees(forRoot:)` は root が本体そのものなら開き直さない（2+N → 1+N）。
  起動時に最近リポジトリの mainRoot 全件をループする（AppDelegate.swift:188-192）ため、
  1 回あたりのオープン回数がエントリ件数倍で効く。
- `indexFingerprint` / `indexURL` は libgit2 に寄せず stat のまま据え置いた。理由を
  `GitRepository` の doc コメントに残した（最頻経路であり、寄せると監視イベント頻度 ×
  ウィンドウ数でリポジトリオープンが増える）。

### 外部 git 方式との差分（意図した変更）

- **bare リポジトリの `worktrees` ルート**: workdir が nil のため gitdir 自体を返す。
  ただし `root(forFileAt:)` が bare で `.notARepository` を返すため、`worktrees` に bare の
  ルートが渡る本番経路は無い（`WorktreeCatalog` は `repositoryIdentity` 由来の mainRoot で呼ばれる）。
- **unborn HEAD（コミット 0 件）の worktree**: `git_repository_head` が `GIT_EUNBORNBRANCH` を
  返すためブランチ名が nil になる。`git worktree list --porcelain` は `branch refs/heads/main` を
  出していたため、表示がディレクトリ名だけに落ちる差分がある。実害は「コミット前のリポジトリを
  worktree サブメニューに出したときの表記」に限られる。
- **ファイル名のエスケープ**: index から生バイトで取るため `core.quotepath` の解除が不要になった。

### テストの移動

`GitRepository.parseWorktreeList` が消えたため、これに紐づくインメモリ網羅テスト 8 ケースを削除し、
worktree 列挙の検証を実 git フィクスチャの Integration テストへ移した（本体含有・ブランチ短縮・
detached・並び順・本体のみのリポジトリ・worktree 側からの列挙）。submodule gitlink の列挙も追加した。

縮退テストの注入点 `UnavailableGitCommandRunner` は使えなくなったため、
`GitLibraryTests.makeUnopenableRepository`（実 git を起動せず `.git/` を手で組む）へ置き換えた。
`.notARepository`（空ディレクトリ）と `.undetermined`（開けないリポジトリ）を対で固定している。

### 検証

- `swift test`: 1406 tests in 205 suites passed（24.1s）
- swiftlint: origin/main とのベースライン差分ゼロ（raw diff も空）
- swiftformat: 全 10 ターゲットで 0 files formatted
- AC #1: `rg 'GitCommandRunn|runner' befold/App/GitRepository.swift` が 0 件
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitRepository の 4 呼び出し（ルート解決・追跡ファイル一覧・worktree 判定・worktree 列挙）を外部 git プロセスから libgit2 へ移行し、GitCommandRunning への依存を解消した。リポジトリは GitLibrary.withRepository 経由でのみ開き、開けなかった場合は .undetermined（キャッシュ不可）、git 管理外が確定した場合は .notARepository（キャッシュ可）へ写像する既存規約を保った。設計レビューを受けて isMain の決め方を配列位置から共通 gitdir 由来の出自へ移し、worktrees のリポジトリオープン回数を 2+N から 1+N へ減らした。検証: swift test 1406 tests passed、swiftlint は origin/main とのベースライン差分ゼロ、AC #1 は GitRepository.swift への rg が 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
