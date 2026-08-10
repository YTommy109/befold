# ADR 0005: git 連携方式を外部 git バイナリ実行から libgit2 へ移行する

- ステータス: Accepted
- 日付: 2026-08-10
- backlog decision: decision-6

<!-- constrained-by ./0003-git-status-guard-in-file-list-model.md -->

## Context

befold の git 連携（サイドバーのステータスバッジ、差分表示、Quick Open の追跡ファイル索引、
worktree 一覧）は、すべて外部 git バイナリの実行で実装されている。
`GitCommandRunner.run` が `/usr/bin/git` を `Process` で起動し、その出力を Swift 側で
パースする形である（`BefoldApp/befold/App/GitCommandRunner.swift:127`）。

### この方式は比較検討を経ていない

libgit2 / SwiftGit2 / ObjectiveGit といった語は、本リポジトリの docs・backlog・git 履歴の
いずれにも 1 件も存在しない。導入コミット `358063c`（2026-07-25）にも方式選択の理由の
記述はなく、事前の計画文書 `docs/superpowers/plans/2026-07-24-clickable-path-resolution.md:430`
の時点で既に Process 前提として書かれている。つまり**ライブラリ方式との比較そのものが
行われていない**。本 ADR はその欠落を埋め、あわせて移行方針を記録する。

### 現状の呼び出し全量（すべて読み取り専用）

| 用途 | 引数 | 実装 |
|---|---|---|
| リポジトリルート解決 | `rev-parse --show-toplevel` | `GitRepository.swift:82` |
| 追跡ファイル一覧 | `ls-files -z` | `GitRepository.swift:97` |
| worktree 判定 | `rev-parse --git-common-dir --git-dir` | `GitRepository.swift:125` |
| worktree 列挙 | `worktree list --porcelain` | `GitRepository.swift:144` |
| 作業ツリー状態 | `--no-optional-locks status --porcelain=v2 -z` | `GitStatusReader.swift:88` |
| submodule パス | `config -z --file .gitmodules --get-regexp` | `GitStatusReader.swift:160` |
| ブランチ差分ファイル | `diff --name-status -z <base> HEAD` | `GitStatusReader.swift:189` |
| 比較起点 | `merge-base HEAD <default>` | `GitComparisonBase.swift:37` |
| 既定ブランチ探索 | `rev-parse --verify --quiet main` / `master` | `GitComparisonBase.swift:53` |
| origin の既定ブランチ | `symbolic-ref --short refs/remotes/origin/HEAD` | `GitComparisonBase.swift:62` |
| 差分本体 | `diff --no-color --no-ext-diff -U1000000 <base> -- <path>` | `GitDiffReader.swift:55` |
| 管理外/コミット無しの切り分け | `rev-parse --git-dir` | `GitDiffReader.swift:73` |
| 未追跡判定 | `ls-files --error-unmatch -z -- <path>` | `GitDiffReader.swift:91` |

commit / add / checkout / fetch は一つも使っていない
（`GitCommandRunner.swift:87` に「befold は読み取り専用ビューア」と明記）。

### 現方式のコスト

`GitCommandRunner`（300 行）の大半は、外部プロセス方式ゆえに必要になった手当てである。

- `core.fsmonitor=` / `core.hooksPath=/dev/null` による任意コマンド実行の遮断（`:77-95`）
- 環境変数の非継承と `PATH` 固定（`:110-120`、TASK-148）
- タイムアウト時のプロセスグループごとの kill と fd 回収（TASK-155）
- `DispatchSemaphore` によるブロック待ち（TASK-226 が未解決のまま残っている）

さらに、依存先はユーザー環境の Xcode Command Line Tools の git であり、
そのバージョン差・未インストール・`~/.gitconfig` の内容がアプリの挙動に影響しうる。

### Mac App Store 配布での決定的な制約

サンドボックス下の子プロセスは **PowerBox 由来の user-selected アクセスを継承しない**。
そのため MAS 版では、ユーザーがフォルダを選択しても `/usr/bin/git` 子プロセスはその
フォルダを読めず、現方式は原理的に成立しない。git 機能を保ったまま MAS へ出すなら、
ライブラリ化（または XPC 分割）が必須になる。

## Decision

git 連携をライブラリ実装へ移行する。バインディングは次の順で評価する。

1. **SwiftGitX**（2025-12 / v0.4.0 / tools-version 6.0 / libgit2 1.9.2 pin）
   — 現在唯一メンテされている Swift バインディング。XCFramework のビルドを肩代わりする
   利点があるが 0.x かつ作者 1 人。
2. **libgit2 を直接**（static XCFramework + `.binaryTarget`）
   — SwiftGitX で必要な API が塞げない場合の本命。SwiftGitX は libgit2 の薄いラッパ
   であるため、後から直接方式へ降りるコストは小さい。

**SwiftGit2 は採用しない。** 最新リリースが 0.6.0（2019-05）、2026 年のコミット 0 件、
master に `Package.swift` が無く SPM 非対応、approve 済み・CI green の SPM 化 PR #208 が
2 年放置されている。Swift 6 strict concurrency を全ターゲットで有効にしている本
プロジェクトの維持コストに見合わない。pure-Swift の git 実装は存在しない。

### libgit2 を「最新 git 機能への追従が速いから」選ぶのではない

この点は明示的に否定しておく。検討中に「jujutsu が採用しているので最新機能の取り込みも
信頼できる」という見立てが挙がったが、事実は逆である。

- **jujutsu は libgit2 を捨てた側**である。v0.26.0（2025-02-05）で push/fetch を外部 git
  プロセスへ移し、v0.27.0（2025-03-05）でそれを既定化、**v0.30.0（2025-06-04）で libgit2
  コードパスを削除**した。現在の git バックエンドは gitoxide（`gix`）。移行理由（issue
  #5548）は SSH 非対応、パッケージング制約（"libgit2 only supports one version at a
  time"）、リモート操作の性能、および「jj has outgrown its need to depend on libgit2」。
- **libgit2 の upstream 追従は実際に遅い。** sparse-checkout は実装 PR #5833 が 2021 年
  から未マージのまま issue は 12.3 年 open、reftable は main にマージ済みだが v1.9.6
  時点で未リリース、partial clone は未対応でリポジトリを開くことすらできない、SHA-256 は
  実験ビルド限定で正式対応は未リリースの v2.0。libgit2 自身も README で "As libgit2 is
  purely a consumer of the Git system, we have to adjust to changes made upstream" と
  遅れを認めている。
- **メンテナ体制は単独依存**。直近 12 か月のコミットの 66% が単一メンテナ。2025 年の
  リリースは実質 2 本。
- **業界の方向は逆**で、GitKraken は「libgit2 が git の機能追加ペースに追いつけない」
  ことを理由に同梱 git バイナリへ移行中。

それでも libgit2 を採るのは、**befold の制約下で他に選択肢が無く、かつ上記の弱点の
ほとんどが befold に当たらない**ためである。

- gitoxide は Rust であり、Swift から使うには FFI 層の自作が必要で libgit2 より重い。
- 同梱 git バイナリ方式（GitKraken の移行先）は、MAS では子プロセスが PowerBox
  アクセスを継承しないため選べない。
- 未対応機能のうち sparse-checkout / bundle URI / SHA-256 / LFS、および GitKraken が
  挙げた LFS・SSH・書き込み操作は、いずれも読み取り専用ビューアの機能に無関係。
- macOS ネイティブアプリでの前例（GitFinder, GitUp, Xit, Xcode 内蔵）は libgit2 側にある。

befold に実際に当たるのは **partial clone と reftable の 2 つだけ**であり、これは
下記のフォールバック方針で扱う。

配布形態は **SPM のソースターゲット**とする（`ibrahimcetin/libgit2` を exact 1.9.2 で
依存に加え、libgit2 の C ソースを SPM ターゲットとしてビルドする）。

<!-- derived-from #consequences -->

> **2026-08-11 追記（実装時の変更）**: 本 ADR は当初 static XCFramework +
> `.binaryTarget` を選んだが、実装（TASK-435.1）で SPM ソースターゲットへ変更した。
> cmake を要さず、XCFramework のビルドと更新を自前で回すコストが丸ごと不要になる。
> 版を `exact` で固定するのは、API/ABI ではなく**リポジトリ形式の対応範囲**が
> 版で変わるため（partial clone / reftable の可否が挙動として効く）。
> Xcode の SPM 統合は C ターゲットへ依存パッケージのヘッダ検索パスを自動では通さないため、
> `project.yml` の `CGitShim` ターゲットへ `HEADER_SEARCH_PATHS` を明示する必要がある。

brew + `.systemLibrary` は dylib パスと
サンドボックスで破綻する。ライセンス（GPLv2 with linking exception）は
"the compiled version" に unlimited permission を与えており、静的リンク・
クローズドソース・MAS 配布のいずれも可能。制約が残るのは libgit2 自体を改変した場合と
ソース vendoring の場合のみ。macOS では `USE_SSH=OFF` / HTTPS を SecureTransport に
することで外部依存をシステム zlib だけに絞れる（読み取り専用の befold にはリモート
通信が不要なため成立する）。

## Consequences

### 得られるもの

- `GitCommandRunner` の外部プロセス起因の手当て（上記 4 項目）が丸ごと不要になる。
  TASK-226（async 化）も、subprocess 待ちが消えることで前提から見直せる。
- ユーザー環境の git バージョンへの依存が切れる。
  起動時に `GIT_OPT_SET_SEARCH_PATH` で config の検索パスを無効化する。

  > **2026-08-11 追記（実装時の変更）**: 無効化するのは **system と xdg の 2 つだけ**で、
  > global（`~/.gitconfig`）は意図して有効のままにする。無効化すると
  > `core.excludesFile` によるグローバルな ignore 設定が効かなくなり、ユーザーが
  > 除外したつもりのファイルがサイドバーに untracked として現れる（実測で libgit2 が
  > `.gitignore` / `.git/info/exclude` / `core.excludesFile` の 3 経路すべてを見ることを
  > 確認済み）。撤去した外部 git プロセス方式も `HOME` を意図的に引き継いで
  > `~/.gitconfig` を有効にしており、その挙動を保つ。
  >
  > また、**無効化の目的は「決定性の確保」であって「任意コマンド実行の遮断」ではない**。
  > 外部プロセス方式では `core.fsmonitor` / `core.hooksPath` が任意コマンドの起動経路に
  > なるため遮断が必須だったが、libgit2 はフックも textconv も外部 diff driver も
  > 実行しないため、その動機は消える。
  > この判断は `GitLibraryTests.keepsGlobalConfigSearchPathEnabled` が守る。
- MAS 配布の最大の障害が外れる（残る障害はサンドボックスと CLI。TASK-397 を参照）。

### 失うもの・引き受けるコスト

- **`git status --porcelain=v2` 相当のヘッダは 5 つの別 API から自前構築が必要**になり、
  `GitStatusReader.parsePorcelainV2` は書き直しになる。
- **submodule status は status API に出ない**（現状の `.gitmodules` 読みは
  `git_submodule_foreach` でむしろ素直になるが、境界検出のロジックは要再設計）。
- **`diff.algorithm` / textconv / 外部 diff driver は config ごと無視**される。
  word-diff も無い。現状これらを使う機能はないが、ユーザーの設定が反映されなくなる。
- **partial clone と reftable 形式のリポジトリは開けない**。今後 git の既定が変わると効く
  （reftable 対応は 2026-08 に libgit2 の main へマージされたが、**未リリース**。
  本 ADR が固定している 1.9.2 には入っていない）
  （下記フォールバック方針で扱う）。
- per-worktree config/refs を扱うには **libgit2 v1.8 以上**が必要。
- ~~直接方式を採る場合、**XCFramework のビルドと更新を自前で回す**ことになる。~~
  → SPM ソースターゲットへ変更したため解消（上記の追記を参照）。

### 影響を受けない箇所

差分の生テキストは Swift 側で構造化せず、`viewer.js:491` の `parseUnifiedDiff` が
JS 側でパースしている。libgit2 の `git_diff_to_buf` は unified diff テキストを出力できる
ため、**JS 側は無改修で済む見込み**（`-U1000000` 相当が `git_diff_options.context_lines`
で表現できることの確認が前提）。

## Fallback

libgit2 がリポジトリを開けない場合（partial clone、reftable、将来の未知の拡張、
`extensions.*` の unsupported 判定全般）、**befold は git 機能だけを静かに落とし、
通常のビューアとして動作を継続する**。エラーダイアログは出さない。

この縮退は新設ではなく、既存の経路へ合流させる。現状 `GitCommandRunner` は結果を
`.output` / `.rejected`（実行できたが非 0）/ `.unavailable`（起動不能・タイムアウト）の
3 値に落としており、呼び出し側は `.unavailable` を「git が使えない環境」として既に
処理している。libgit2 でリポジトリを開けなかった場合はこの `.unavailable` 相当へ
写像する。したがって表示側の分岐は増えない。

対象となる縮退の内容:

- サイドバーの git ステータスバッジを表示しない
- 差分表示モードを選択不可にする（既存の「管理外」扱いと同じ）
- Quick Open の候補列挙を、追跡ファイル索引ではなくディレクトリ走査へ切り替える
  （`DirectoryFileScanner` による既存経路がある）

**この方針は「破れたら落ちるもの」で担保する。** 開けないリポジトリを模したフィクスチャ
（`extensions.partialclone` を設定した `.git/config` 等）を用意し、それを開いたときに
クラッシュせず・ダイアログを出さず・ビューアとしては通常どおり動くことをテストする。
実装時に確認しやすいよう `.unavailable` 相当へ写像する箇所は 1 関数に集約する。

なお、この方針は「git 機能が使えないことをユーザーに一切伝えない」という意味ではない。
何も伝えないと ADR 0003 の Context にある「原因不明の無反応」と同じ形になるため、
伝え方（サイドバーの控えめな注記など）は実装時に決める。ただしモーダルでの中断は取らない。

### 実装前に潰すべき未確認事項

- libgit2 がサンドボックスコンテナの HOME を引くかの実測
- `.git` 配下の flock / rename のサンドボックス下での挙動
- `.gitignore` 判定が `core.excludesFile` / `info/exclude` を見るか
- libgit2 起因の App Store リジェクト事例の有無

> **2026-08-11 追記**: 移行（TASK-435）完了時点で解消しているのは 3 番目だけである。
> libgit2 は `.gitignore` / `.git/info/exclude` / `core.excludesFile` の 3 経路すべてを
> 見ることを実測で確認し、その結果 global config を無効化しない判断に至った（上記）。
>
> 残る 3 点はいずれも **App Sandbox を有効にして初めて確かめられる**もので、
> 本移行の範囲外である。befold は現時点でサンドボックス化されておらず
> （security-scoped bookmark は 0 件）、MAS 配布には他の障害（Sparkle 撤去、CLI の扱い）も
> 残る。MAS 対応に着手する際の前提条件として TASK-397 が引き取る。
