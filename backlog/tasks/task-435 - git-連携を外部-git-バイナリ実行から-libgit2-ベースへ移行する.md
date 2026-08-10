---
id: TASK-435
title: git 連携を外部 git バイナリ実行から libgit2 ベースへ移行する
status: In Progress
assignee:
  - '@Tommy109'
created_date: '2026-08-10 13:13'
updated_date: '2026-08-10 15:33'
labels:
  - refactor
dependencies: []
priority: high
type: task
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold の git 連携（サイドバーのステータスバッジ、差分表示、Quick Open の追跡ファイル索引、worktree 一覧）は、すべて GitCommandRunner が /usr/bin/git を Process で起動する方式で実装されている。この方式はライブラリ方式との比較検討を経ずに採用されており（docs/adr/0005 の Context 参照）、次のコストを恒常的に負っている。

1. GitCommandRunner（300 行）の大半が外部プロセス起因の手当て — core.fsmonitor/core.hooksPath による任意コマンド実行の遮断、環境変数の非継承と PATH 固定（TASK-148）、タイムアウト時のプロセスグループ kill と fd 回収（TASK-155）、DispatchSemaphore によるブロック待ち（TASK-226 が未解決）
2. ユーザー環境の Xcode Command Line Tools の git に依存する — バージョン差・未インストール・~/.gitconfig の内容が挙動に影響する
3. Mac App Store 配布では原理的に成立しない — サンドボックス下の子プロセスは PowerBox 由来の user-selected アクセスを継承しないため、ユーザーがフォルダを選んでも子プロセスの git はそれを読めない

方針・トレードオフ・不採用としたライブラリ（SwiftGit2）の根拠は docs/adr/0005-git-integration-via-libgit2.md（decision-6, Proposed）に記録済み。バインディングは SwiftGitX を先に評価し、必要な API が塞げない場合に libgit2 直接（static XCFramework + .binaryTarget）へ降りる。

現状の呼び出しは 13 箇所ですべて読み取り専用（commit/add/checkout/fetch なし）のため、認証・credential helper・push 系は移植対象外。差分の生テキストは Swift 側で構造化せず viewer.js の parseUnifiedDiff が JS 側でパースしているため、git_diff_to_buf で unified diff を出せれば JS 側は無改修で済む見込み。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ADR 0005 の「実装前に潰すべき未確認事項」4 点が実測で解消され、結果が Implementation Notes に記録されている
- [ ] #2 docs/adr/0005 の呼び出し一覧 13 箇所すべてがライブラリ実装に置き換わり、プロダクトコードから /usr/bin/git の Process 実行が消えている
- [ ] #3 -U1000000 相当の全文コンテキスト diff が再現され、viewer.js の parseUnifiedDiff が無改修で従来どおり描画できる（差分表示の既存テストが通る）
- [ ] #4 porcelain=v2 相当のステータス取得が再実装され、GitStatusReader の既存テストが同等の期待値で通る
- [ ] #5 worktree 列挙・submodule 境界検出・比較起点の解決が従来と同じ結果を返す
- [ ] #6 GitCommandRunner の外部プロセス起因の手当て（fsmonitor/hooksPath 遮断・環境変数遮断・プロセスグループ kill）が不要になったぶん撤去されている
- [ ] #7 起動時に GIT_OPT_SET_SEARCH_PATH で system/xdg の config を無効化し、global（~/.gitconfig）は core.excludesFile によるグローバル ignore を保つため意図して有効のままにする。両方の判断がテストで担保されている
- [ ] #8 SwiftGitX を先に評価し、必要な API が塞げるかの判断結果（採用したバインディングとその理由）が Implementation Notes に記録されている
- [ ] #9 libgit2 が開けないリポジトリ（partial clone / reftable）を模したフィクスチャで、クラッシュせず・モーダルを出さず・通常のビューアとして動作することがテストで担保されている
- [ ] #10 リポジトリを開けなかった場合に .unavailable 相当へ写像する箇所が 1 関数に集約されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 【完了】事前調査（AC #1 / #8）。ADR の未確認 4 点を実測で解消し、SwiftGitX を評価して不採用と判断した。結果は Implementation Notes に記録済み。
2. サブタスクへ分割して順に実施する。各サブタスクの着手前に `/review-design` を 1 回回す（CLAUDE.md「実装着手前の設計レビュー」）。
   - TASK-435.1 基盤: libgit2 の SPM 依存追加・C シムターゲット・リポジトリオープンの 1 関数集約（AC #7 / #9 / #10）
   - TASK-435.2 GitRepository の移行（root 解決 / 追跡ファイル一覧 / worktree 判定・列挙。AC #5 の一部）
   - TASK-435.3 GitStatusReader の移行（porcelain=v2 相当 / submodule 境界 / ブランチ差分。AC #4、AC #5 の一部）
   - TASK-435.4 GitDiffReader + GitComparisonBase の移行（全文コンテキスト diff / 比較起点。AC #3、AC #5 の一部）
   - TASK-435.5 GitCommandRunner の撤去・テスト整理・ADR 0005 の更新（AC #2 / #6）
3. 分割方針の根拠: 現行の 4 つの読み取り実装（GitRepository / GitStatusReader / GitDiffReader / GitComparisonBaseResolver）はいずれも `GitCommandRunning` を注入される独立した seam であり、1 つずつ libgit2 実装へ差し替えても呼び出し側とテストの seam は変わらない。したがって「共通基盤 → 個別の実装 → 旧実装の撤去」の順で、各段階を動作する状態に保ったまま進められる。
4. ADR 0005 の更新点（TASK-435.5 で反映）: (a) 配布形態を static XCFramework から SPM ソースターゲットへ変更、(b) core.excludesFile が効かなくなることを Consequences へ追記、(c) グローバル config 無効化の目的が「任意コマンド実行の遮断」ではなく「決定性の確保」である旨を明記。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 関連タスク

- TASK-226（GitCommandRunner の async 化）: 本タスクが着地すれば subprocess 待ちそのものが消えるため、TASK-226 は前提から見直しになる。どちらを先にやるかは本タスクの採否が決まってから判断する（先に TASK-226 を実施すると、撤去予定のコードに対して 18 ファイル規模の改修を投じることになる）。
- TASK-397（オープンソースのままバイナリを販売する場合の配布・課金モデルを ADR にまとめる）: Mac App Store 配布を選ぶ場合、本タスクは必須の前提条件になる。ただし MAS 対応には他にも App Sandbox 有効化（security-scoped bookmark が現状 0 件）、Sparkle 撤去、CLI（/usr/local/bin への symlink + NSAppleScript 昇格、DistributedNotificationCenter）の扱いという別の障害があり、本タスク単独では MAS 対応は完了しない。

## 着手条件

MAS 対応と切り離しても、上記 1・2 のコスト解消という独立の価値がある。ただし ADR 0005 は Proposed のままであり、着手前にユーザーと方針を確定すること。

## 方針確定（2026-08-10）

ADR 0005 は Accepted。libgit2 ベースへの移行を採用する。

採用理由が「最新 git 機能への追従が速いから」ではない点に注意（ADR 0005 の該当節を参照）。実際には jujutsu は v0.30.0 で libgit2 を削除して gitoxide へ移行しており、libgit2 の upstream 追従は遅い（sparse-checkout の issue は 12.3 年 open、reftable は未リリース、partial clone は未対応）。採用根拠は「Swift から使える現実的な選択肢が libgit2 系しかなく、かつ未対応機能の大半が読み取り専用ビューアに当たらない」こと。

これに伴い、開けないリポジトリのフォールバック（git 機能のみ静かに無効化し通常のビューアとして継続）を ADR の Fallback 節に追加し、AC #9 / #10 で担保する。

## 優先順位の整理(2026-08-10)

Priority を medium → high へ引き上げ、To Do の 2 番目(TASK-427 の次)へ置いた。

**引き上げの根拠は「テスト安定性」ではなく順序制約**である。着手順を誤ると手戻りが出る下流タスクが 3 件ある。

- TASK-226(GitCommandRunner の async 化): 本タスクが着地すれば不要になる。先にやると撤去予定コードへ 18 ファイル規模の改修を投じる(本タスク Notes の「関連タスク」節)
- TASK-353(差分の比較基準の切り替え): GitDiffLoader を触る feature。先にやるとバックエンド差し替え時に作り直しになる
- TASK-187(サイドバー Git ステータスの stable 昇格): subprocess 版を stable に出してから差し替えることになる

### テスト安定性への寄与の実測(サブエージェント調査、2026-08-10)

「libgit2 化でテストが安定する」は**部分的にしか支持されない**。優先度の根拠として過大評価しないこと。

支持される点:
- `GitCommandRunnerResourceLeakTests` 7 本(GitCommandRunnerTests.swift:285-506、約 285 行 + ヘルパー 200 行)が丸ごと不要になる。スイート実測 8.245 秒で、うち約 7.2 秒は「猶予の満了を待つこと自体が検証」であるためテスト側の工夫では縮まらない(AC #6 の撤去対象)
- 外部プロセス起因のフレーク起票が過去 7 件(TASK-157/158/244/245/255/312/350)。うち CI 実失敗 2 件(TASK-312/350)、テストプロセスごとクラッシュしうる構造 1 件(TASK-158)
- `GitTestRepo.swift:25` の上限なし `waitUntilExit()`(TASK-424 の Notes が「未対処、記録のみ」と明記)が構造的に消える
- @MainActor テスト 6 本が `Process.waitUntilExit()` で main actor をブロックしながら git を起動する経路(TASK-312 で実測)が無くなる

支持されない点:
- 直近の CI 不安定 2 件は git 起因ではない。TASK-424 のハングは `GitStatusStoreTests.FakeReader.status` と `GitCommandFileIndexConcurrencyTests` の `BlockingRepository.trackedFiles` という**フェイク**のセマフォ枯渇であり実 git は起動していない。TASK-427 は `SlowFileReader`。どちらも本タスクでは改善しない
- spawn 回数の削減が実行時間に効かないことは TASK-244(正味ゼロ)・TASK-245(効果ほぼ無し)で 2 回実測否定済み。効いたのは TASK-255 の猶予短縮のみで手当て済み
- TASK-255 以降のクリティカルパスは `ViewerStoreIntegrationTests`(約 10 秒)で、git 系は既に律速ではない。フル実行の短縮は律速交代分に留まる
- 実 git を起こすテストは 1390 本中 44 本(3.2%)

## AC #1: 実装前に潰すべき未確認事項 4 点の実測結果（2026-08-10）

実測環境: 検証用 SPM パッケージをスクラッチパッドに作り、libgit2 を直接呼ぶプローブを書いて計測した。
libgit2 は `ibrahimcetin/libgit2`（SwiftGitX が pin する SPM ソースパッケージ）1.9.2 タグ。
`git_libgit2_version` の自己申告は 1.9.0。ホスト側の比較対象は PATH 上の git 2.55.0。

### (1) libgit2 がサンドボックスコンテナの HOME を引くか → 引く（HOME 環境変数由来）

`git_libgit2_opts(GIT_OPT_GET_SEARCH_PATH, ...)` の実測値:

| HOME | SYSTEM | XDG | GLOBAL | ~/.gitconfig の user.name |
|---|---|---|---|---|
| 実ホーム | `/etc` | `$HOME/.config/git` | `$HOME` | 読める |
| 差し替えた偽ホーム | `/etc` | 偽ホーム/.config/git | 偽ホーム | 偽ホーム側の値が読める |
| 未設定（`env -u HOME`） | `/etc` | `""` | `""` | 読めない |

GLOBAL/XDG は HOME 環境変数からのみ導出され、HOME 未設定時に getpwuid へフォールバックしない。
App Sandbox では HOME がコンテナの Data ディレクトリへ書き換わるため、libgit2 はコンテナ内を見る
（＝実ユーザーの ~/.gitconfig は読まない）。さらに AC #7 の無効化を入れれば HOME の値によらず無関係になる。

`befold_git_opts_set_search_path(level, "")` を SYSTEM/XDG/GLOBAL に対して実行後、
3 レベルとも `""` になり `git_config_open_default` から user.name が消えることを実測（rc=-3）。AC #7 は実現可能。

### (2) .git 配下の flock / rename のサンドボックス下での挙動 → 書き込み不要で成立する

`sandbox-exec` でフィクスチャ配下を書き込み禁止にして計測。

- `.git` 書き込み禁止: status（7 エントリ）・diff・worktree 列挙・submodule 列挙・index 走査すべて成功。
  クラッシュもハングも無し。`.git/index` の更新は発生しない。
- `.git` 読み取り禁止: `git_repository_open` が `-3`(GIT_ENOTFOUND) / klass=6(GIT_ERROR_REPOSITORY) で
  即座に失敗。クラッシュもハングも無し。`.unavailable` へ写像すれば足りる。

読み取り専用アクセスだけで現状の 13 呼び出し相当が成立することを実測で確認した。

### (3) .gitignore 判定が core.excludesFile / info/exclude を見るか → **3 つとも見る**

`git_ignore_path_is_ignored` の実測（同じフィクスチャに 3 経路の無視対象を用意）:

| 対象 | .gitignore | .git/info/exclude | core.excludesFile |
|---|---|---|---|
| HOME に core.excludesFile あり | ignored=1 | ignored=1 | ignored=1 |
| HOME に設定なし | ignored=1 | ignored=1 | ignored=0 |

実 git の `status --porcelain=v2` と完全一致した。

**ここに AC #7 とのトレードオフがある。** core.excludesFile はグローバル config 経由で読まれるため、
AC #7 の `GIT_OPT_SET_SEARCH_PATH` 無効化を入れると **core.excludesFile が効かなくなる**。
現行の subprocess 実装は `GitCommandRunner.processEnvironment()` で HOME を意図的に残しており
（`GitCommandRunner.swift:111-112` に「ユーザー自身の ~/.gitconfig は信頼できる設定」と明記）、
グローバル ignore は現在は効いている。移行後はグローバル ignore していたファイルが
サイドバーに untracked バッジで出るようになる。AC #7 を書いたとおり実装するが、この挙動変化は
Consequences として ADR へ追記する。

なお、無効化の主目的は現状（subprocess）とは異なる点に注意する。subprocess では
core.fsmonitor / core.hooksPath が任意コマンド実行の経路になるため遮断が必須だったが、
libgit2 はフックも textconv も外部 diff driver も実行しない。libgit2 での無効化目的は
「決定性の確保」であって「任意コマンド実行の遮断」ではない。

### (4) libgit2 起因の App Store リジェクト事例の有無 → 公開情報では見つからなかった

複数クエリで検索したが、libgit2 の同梱を直接の理由とするリジェクト事例は発見できず。
「事例が無い」ことの証明ではないため、**未確認のまま残るリスクとして記録する**。
関連する既知の issue は libgit2#6883（Apple のシステム gitconfig を見つけられない）、
libgit2#6182 / #4815（GIT_CONFIG 系環境変数を本家ほど尊重しない）で、いずれも
「環境変数トリックではなく GIT_OPT_SET_SEARCH_PATH で明示的に無効化せよ」という方向を支持する。
サンドボックス対策として同じ手法を採る先行実装がある（stagit が OpenBSD の unveil 対策で
`for (i = 1; i <= GIT_CONFIG_LEVEL_APP; i++) git_libgit2_opts(GIT_OPT_SET_SEARCH_PATH, i, "")` を実施）。

## AC #8: バインディングの評価結果 → SwiftGitX は不採用、libgit2 を直接叩く

ADR 0005 の指示どおり SwiftGitX を先に評価した。結論は**不採用**。befold が必要とする 13 呼び出しのうち
過半が SwiftGitX の公開 API に存在しない。

| 必要な機能 | SwiftGitX | 根拠 |
|---|---|---|
| status（HEAD/index/worktree の 3 者比較、rename 検出） | ある | `Repository+status.swift` が `git_status_list_new` を呼び、`StatusEntry` が index/workingTree の Delta を別々に持つ |
| ブランチ存在確認 / 任意フルネーム参照の解決 | ある | `BranchCollection` / `ReferenceCollection` |
| unified diff テキスト生成 + context 行数指定 | **無い** | `Repository+diff.swift` は diff options を常に `nil` で渡す。`// TODO: Implement diff options` のコメントあり。`context_lines` の出現 0 件、`git_diff_to_buf` 相当も無し |
| pathspec 限定の diff | **無い** | 同上（path 引数が API に無い） |
| worktree 列挙 | **無い** | Worktree 型が存在しない |
| submodule 列挙 | **無い** | Submodule 型が存在しない |
| merge-base | **無い** | `merge_base` の出現 0 件 |
| 追跡ファイル一覧（ls-files 相当） | **無い** | `IndexCollection` は internal かつ add/remove のみ |
| `git_libgit2_opts`（AC #7 の前提） | **無い** | `GIT_OPT` の出現 0 件 |

したがって **libgit2 の C API を直接使う**。ただし ADR が想定した「static XCFramework + `.binaryTarget`」は採らない。

### 配布形態の変更提案: XCFramework をやめて SPM ソースターゲットにする

SwiftGitX の依存先である `ibrahimcetin/libgit2` は、**libgit2 の C ソースを SPM の C ターゲットとして
そのままビルドするパッケージ**であり、`.library(name: "libgit2", targets: ["libgit2"])` を product として
公開している。アプリ側から直接依存に加えて `import libgit2` できることを実測で確認した。

- macOS 向けに CommonCrypto / SecureTransport / builtin zlib・pcre・llhttp・xdiff を選ぶ設定が
  `Package.swift` に書かれており、ADR が挙げた `USE_SSH=OFF` 相当・SecureTransport 化は済んでいる
- ローカルでのビルド実測: 依存解決 + フルビルドが **6.4 秒**（286 ステップ）。cmake は不要
  （このマシンには cmake が入っていないが問題なくビルドできた）
- ADR が「引き受けるコスト」に挙げた「XCFramework のビルドと更新を自前で回す」が消える

既製の XCFramework パッケージ（`bdewey/static-libgit2` = libgit2 1.3.0 / 2022 年停止、
`light-tech/Clibgit2` = 2021 年停止・ライセンス記載なし）はいずれも古く、採れない。

### `git_libgit2_opts` は C 可変長引数のため Swift から呼べない → C シムが要る

`GIT_EXTERN(int) git_libgit2_opts(int option, ...);` は真の C 可変長引数関数であり、Swift から直接
呼び出せない（Clang importer が取り込まない）。SwiftGitX にも `ibrahimcetin/libgit2` にもシムは無い。
固定引数へ落とす小さな C ターゲットを befold 側に置く必要がある。実測で動作を確認したシム:

```c
int befold_git_opts_set_search_path(int level, const char *path) {
    return git_libgit2_opts(GIT_OPT_SET_SEARCH_PATH, level, path);
}
```

### 開けないリポジトリの判定は 1 種類に収束する（AC #9 / #10 の裏付け）

`core.repositoryformatversion >= 1` かつ未知の `extensions.*` があると `git_repository_open` が
`-1` / klass=6(GIT_ERROR_REPOSITORY) / `unsupported extension name extensions.<名前>` で失敗する。
フィクスチャ 3 種で実測し、すべて同じ形になった。

| フィクスチャ | libgit2 | 実 git 2.55 |
|---|---|---|
| `extensions.partialClone` | -1 / `unsupported extension name extensions.partialclone` | 開ける |
| `--ref-format=reftable` | -1 / `unsupported extension name extensions.refstorage` | 開ける |
| 未知の `extensions.befoldUnknown` | -1 / `unsupported extension name extensions.befoldunknown` | 開けない（fatal） |

判定が 1 経路に収束するため、AC #10 の「`.unavailable` 相当へ写像する箇所を 1 関数に集約」は素直に書ける。

補足: reftable 対応は 2026-08-06〜07 に libgit2 の main へマージされたが、まだどのタグ付きリリースにも
入っていない（tracking issue #5352 は open のまま）。1.9.x を使う限り上表のとおり開けない。

## AC #3 / #4 / #5 の実現可能性（実測で確認済み）

### unified diff は実 git とバイト一致した（AC #3）

`git_diff_options.context_lines = 1_000_000` + `git_diff_tree_to_workdir_with_index` +
`git_diff_to_buf(GIT_DIFF_FORMAT_PATCH)` の出力が、
`git diff --no-color --no-ext-diff -U1000000 HEAD -- tracked.txt` の出力と**バイト単位で一致**した
（`diff --git` / `index 624784e..427f750 100644` / `@@ -1,6 +1,6 @@` まで含めて同一）。
viewer.js の `parseUnifiedDiff` は無改修で足りる見込みが実測で裏付けられた。

### status は porcelain=v2 と 1 対 1 に対応した（AC #4）

同一フィクスチャ（staged 追加 / workdir 削除 / rename / staged 変更 / workdir 変更 / untracked 2 件）で比較:

| ファイル | 実 git porcelain=v2 | libgit2 head_to_index / index_to_workdir |
|---|---|---|
| added.txt | `1 A.` | ADDED(1) / UNMODIFIED(0) |
| deleted.txt | `1 .D` | UNMODIFIED(0) / DELETED(2) |
| renamed-again.txt | `2 R.` + 元パス | RENAMED(4) / UNMODIFIED(0)、old_file.path に元パス |
| staged.txt | `1 M.` | MODIFIED(3) / UNMODIFIED(0) |
| tracked.txt | `1 .M` | UNMODIFIED(0) / MODIFIED(3) |
| untracked.txt, ignored-by-excludesfile.txt | `?` | UNMODIFIED(0) / UNTRACKED(7) |

エントリ数・パス・rename の元パスまで一致。XY の 2 文字は
`head_to_index.status` と `index_to_workdir.status` を `git_delta_t` → 文字へ写像すれば再現できる。

### worktree / submodule / 比較起点（AC #5）

`git_worktree_list` + `git_worktree_lookup` + `git_worktree_path`、`git_submodule_foreach`、
`git_merge_base`、`git_branch_lookup`、`refs/remotes/origin/HEAD` の `git_reference_symbolic_target`、
`git_repository_path` / `git_repository_commondir` / `git_repository_is_worktree`、
index 走査（ls-files 相当）がいずれも動作することを実測。

**移行時の差分として拾うべき点が 2 つある。**

1. `git_worktree_list` は**リンク worktree だけ**を返し、メイン worktree を含まない。
   現行の `git worktree list --porcelain` はメインも含む（`GitRepository.parseWorktreeList`）。
   メイン側は `git_repository_commondir` から自前で補う必要がある。
2. `git_worktree_*` はブランチ名を返さない。各 worktree を開いて HEAD を読む手当てが要る。

### その他の実装上の注意（実測で判明）

- `git_error_last()` は成功後も直前のエラーが残る（`git_repository_open` が rc=0 でも
  `.git/shallow` の stat 失敗が残っていた）。**rc < 0 のときだけ読む**こと。
<!-- SECTION:NOTES:END -->
