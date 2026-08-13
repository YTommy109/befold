# サイドバー Git ステータス表示 設計

<!-- derived-from ./2026-07-28-code-font-settings-design.md -->

> **これは 2026-07-28 時点の設計スナップショットです。**
> 現在の仕様は [`docs/dev/native-app-design.md`](../../dev/native-app-design.md)
> が単一の情報源。この文書は当時の意図と検討経緯を残すためのもので、
> 現在の実装と食い違っていることがある。着手前に必ずコードで裏を取ること。

サイドバーのファイル一覧で、Git リポジトリ内の変更ファイルに状態バッジを表示する。
ステージ済み(index) / 未ステージ(worktree) / untracked(新規) を区別し、
さらに現在ブランチが base ブランチから変更したコミット済みファイルにもマークを付ける。

本機能は **フィーチャーゲート対象**（`FeatureGate.inProgressFeaturesEnabled`）とし、
stable 昇格までは dev / DEBUG ビルドでのみ露出する。

## 背景

現状の Git 連携（`GitRepository`, `GitCommandRunner`, `GitCommandFileIndex`,
`TrackedPathResolver`, `ReferenceResolutionCoordinator`）は「文書内パス参照のリンク化・
解決」と「相対パスコピーの基準決定」専用で、git status / 差分は扱っていない。

サイドバー（`FileListView` / `FileListEntryRow` / `FileListModel`, 駆動役
`SidebarNavigator`）は現在ディレクトリの実ファイル列挙（`DirectoryLister`）を表示するのみ。

## スコープ

### やること

- Git status（porcelain v2）による staged / unstaged / untracked の判別とバッジ表示
- base ブランチ（デフォルトブランチ自動検出）との merge-base 比較による
  「ブランチ内変更」ファイルのバッジ表示
- サイドバー行右端への 1 文字バッジ + 色表示
- フィーチャーゲートによる露出制御

### やらないこと

- ステージ/アンステージ等の Git 操作 UI（表示のみ、read-only）
- 行/ハンク単位の差分表示
- ユーザーによる base ブランチのカスタム設定（将来検討）
- サイドバー以外（タブ・プレビュー内 FolderListingView）へのバッジ表示

## 表示仕様

行右端に 1 文字バッジ + 色。状態は最大 4 種の組み合わせ。

| 状態 | バッジ | 色（目安） |
| ---- | ------ | ---------- |
| staged (index 変更) | `A` / `M` / `D` 等（index 側コード） | 緑系 |
| unstaged (worktree 変更) | `M` / `D` 等（worktree 側コード） | 橙系 |
| untracked (新規) | `?` | 灰系 |
| branchModified (コミット済み・作業ツリークリーン) | `M` | 青系 |

**staged + unstaged 両立時**: バッジ文字は **index 側を優先表示**しつつ、
色で worktree 変更も示す（例: 文字は緑の index コード、加えて橙のアクセントを添える）。

Phase 1 実装では、アクセントを**文字の左に置く直径 4pt の橙の丸**にした
（文字を 2 つ並べると行幅を食い、ファイル名の切り詰めが早まるため）。
バッジ文字は 10pt の等幅セミボールド。

バッジ非表示となるのは: 非 Git リポジトリ / git 不在 / status 取得失敗 / 変更なし。

## アーキテクチャ

### 配置とモジュール境界

<!-- constrained-by #背景 -->

`GitStatusReading` / `GitStatusReader` / `GitFileStatus` / `GitStatusSnapshot` は
**すべて `befold/App/` に置く**（`BefoldKit` には置かない）。`BefoldKit` はサンドボックス下の
QuickLook 拡張（`BefoldQuickLook`）がリンクしており、Process を spawn するコードを
持ち込めないため。既存の `GitRepository` / `GitCommandRunner` / `GitCommandFileIndex` が
App 側にあるのと同じ理由。

porcelain パースやバッジ写像などの純粋ロジックも BefoldKit へ出す必要はない。
`GitRepository.parseWorktreeList` と同じ「App 型の static 純関数 + インメモリ・
フィクスチャの単体テスト」で足りる。

### GitStatusReading / GitStatusReader（新規）

`GitCommandRunner` を用いてリポジトリルート単位で status を取得する。

```
protocol GitStatusReading: Sendable {
    // ルート配下の変更ファイルを status 付きで返す
    func status(forRepositoryAt root: URL) -> GitStatusSnapshot?
}
```

`GitStatusReader` の実装が呼ぶ git コマンド:

- `git --no-optional-locks status --porcelain=v2 -z`
  → 各パスの XY コード（X=index 側, Y=worktree 側）から staged / unstaged / untracked を判別。
  `--no-optional-locks` は **必須**（下記「更新契機」の自己励振ループ対策）。
- デフォルトブランチ検出: `git symbolic-ref --short refs/remotes/origin/HEAD`
  （無ければローカル既定 main/master を試行）。検出不可なら branch 差分はスキップ。
- `git merge-base HEAD <default>` → base コミット
- `git diff --name-status -z <mergeBase> HEAD`
  → ブランチ内でコミット済みの変更ファイル（branchModified）

Phase 3 実装時の確定事項（2026-08-02）:

- デフォルトブランチの検出順は `origin/HEAD` → ローカル `main` → ローカル `master`。
  どれも解決できなければ branchModified だけを諦める（他の状態はそのまま出す）。
- ブランチ差分の取得は status 1 回につき最大 3 プロセス（`symbolic-ref` または
  `rev-parse` / `merge-base` / `diff`）を追加する。契機がイベント駆動（Phase 2）で
  連打されないこと、`GitStatusStore` が in-flight を畳むことが前提。
- `--name-status -z` は「状態」と「パス」が別フィールドで並び、改名・複製だけ
  パスが 2 つ続く。読み進める数を状態で変えないと以降の対応がずれる。

すべて `GitCommandRunner.hardeningOptions` を通す。`GitCommandOutcome` の扱いは
既存規約（`GitCommandFileIndex`）を踏襲し、**`.rejected`（実行できたが非 0）は結果として
キャッシュしてよいが、`.unavailable`（起動不能・タイムアウト）はキャッシュしない**。
どちらも表示上は「status 無し」に縮退する。

`.git` 参照解決（ワークツリー / submodule）は Reader 側で直接扱わない。
`GitRepository.gitDirectory(at:)` は private のため、公開済みの
`GitRepository.indexFingerprint(at:)` を用い、**Reader が取得時点の fingerprint を
`GitStatusSnapshot` に同梱して返す**。これにより Store の依存シームは
`GitStatusReading` 1 本に閉じる。

### GitFileStatus（新規）

各ファイルの状態を表す値型。表示層で「バッジ文字 + 色」へ写像する（写像は表示側の純粋関数）。

当初は `OptionSet` を想定していたが、**Phase 1 実装時に構造体へ変更した**。バッジ文字は
「index 側の変更種別（A / M / D …）そのもの」を出す仕様であり、フラグの集合からは
文字を復元できないため。実際の形は
`indexChange: Change?` / `worktreeChange: Change?` / `isUntracked` / `isBranchModified` で、
組み合わせ（staged かつ unstaged など）は「どちらの辺が nil でないか」で表現する。

### GitStatusSnapshot（新規）

1 リポジトリルート分の `[String: GitFileStatus]` マップ + 取得時点の
`.git/index` fingerprint（`GitRepository.indexFingerprint(at:)` 由来）。

キーは **`URL` ではなく `normalizedPathKey`（String）** とする。リポジトリ全体の規約
（`PathKeyedDictionary` / `WorktreeCatalog` / `FileListEntry.pathKey`）に合わせるため。
URL をキーにすると symlink 経由の別表記で一致せず、`FileListEntry` との突合が落ちる。

キーは**リポジトリルート相対ではなく解決済みの絶対パス**にする（Phase 1 実装時に確定）。
`normalizedPathKey` は `resolvingSymlinksInPath()` でファイルシステムに触るため、
メインアクター外で動く Reader 側で変換を済ませ、メインスレッドでの stat を避ける。
`FileListEntry.pathKey` と同じ形になるので、表示側は絞り込みも変換もなしに引ける。

### GitStatusStore（新規、@MainActor @Observable）

リポジトリルート単位で `GitStatusSnapshot` をキャッシュし、全ウィンドウで共有する。

踏襲する先例は **`WorktreeCatalog`**（`@MainActor` キャッシュ + `Task.detached` で git 実行 +
in-flight `Task` 辞書で重複実行を畳む + 結果だけ MainActor に反映）。
`GitCommandFileIndex` の `NSLock` / `KeyedLock` 直列化は**踏襲しない** —
`@MainActor` 上でロックを握って subprocess を待つ形になり噛み合わないため。
結果として `KeyedLock` の抽出も LRU 実装の複製も不要。

`.git/index` fingerprint 変化でスナップショットを無効化する。

**ルート解決は共有 `gitFileIndex`（`GitFileIndexing.repositoryRoot(forDirectoryAt:)`）に
一本化する**。Store が独自に `GitRepository` を生成して rev-parse を重ねてはならない
（`AppQuickOpenEnvironment` に同趣旨の明示規約あり）。

Git 無効時のフォールバックとして `DisabledGitFileIndex` に相当する
no-op 実装（常に nil を返す）を既定値に用意する。

### 注入経路

`AppDelegate.init` で生成（`WorktreeCatalog` と同じ位置）→ `ViewerWindowManager` が保持 →
`ViewerWindowController` へ forward → `SidebarNavigator` へは `resolveGitRoot` と同型の
クロージャで注入する（SidebarNavigator が git 型に直接依存せず、既存テストが壊れない）。
`ViewerWindowController` の既定値は no-op 実装とし、テストが git を spawn しないことを保証する。

Store が要る共有 `gitFileIndex` の実体は `ViewerWindowManager` が握っている（既定引数で
生成される）ため、`AppDelegate` は **windowManager を生成した直後にルート解決付きの
Store を差し込む**形にする（`windowManager.gitStatusStore = GitStatusStore(...)`）。
`ViewerWindowManager` / `ViewerWindowController` の既定値はルート解決が常に nil を返す
無効化状態で、注入を省略したテストは git を起動しない。

### FileListModel / FileListEntryRow（既存を拡張）

- `FileListModel` に `pathKey -> GitFileStatus` の参照手段を持たせる
  （`GitStatusStore` から現ディレクトリ分を引く）。
- `FileListEntryRow` の `.file`（必要なら `.folder`）分岐に status バッジを追加描画。

**行の再描画に関する注意**: `FileListView` の `List(model.visibleEntries, selection:)` の
行ビルダークロージャは（NSTableView 裏打ちのため）遅延評価される。マップを
クロージャ内で読むと観測トラッキングのスコープ外になり、**あとから status マップだけ
差し替えても行が再描画されない**。対策として `FileListEntryRow` に
`status: GitFileStatus? = nil` のデフォルト引数を足し、**行ビューの body 内で status を
読ませる**（行ごとに独立して観測登録される）。デフォルト引数にすることで、
`FileListEntryRow` を共有している `FolderListingView` は無変更で済む
（バッジをサイドバー外に出さない本スコープとも整合）。

`.folder` 行は右端に `chevron.right` が既にあるため、フォルダーにもバッジを出す場合は
chevron との並びを決める必要がある。`.file` 行は `Spacer()` の後が空で余地がある。

### SidebarNavigator（既存を拡張）

`refreshFileList` の後段で `GitStatusStore` に現ディレクトリの status を問い合わせ、
`FileListModel` に反映する。

実装は既存の `refreshBaseDirectory`（メイン外で git 解決 → 世代ガード → MainActor で
model に書き戻す）と同型にし、**第 3 の世代番号**を足す形にする。
`cancelPendingListing()` に status タスクのキャンセルを追加することを忘れない
（`windowWillClose` から呼ばれる）。

## データフロー

```
SidebarNavigator.refreshFileList
  → GitStatusStore.status(forDirectory:)   （ルート解決 + キャッシュ or git 実行）
  → FileListModel に pathKey→GitFileStatus を反映
  → FileListEntryRow が右端に 1 文字バッジ + 色を描画
```

Reader が返すのはリポジトリルート相対のパスなので、Store 側で表示中ディレクトリ分に
絞り込んでから `FileListModel` に渡す。

## 更新契機

1. サイドバー refresh 時（ディレクトリ移動・初回表示）
2. ウィンドウがキー化した時（フォーカス復帰）
   — 既存の `windowDidBecomeKey → refreshFileList()` に相乗りでき、追加フックは不要
3. 作業ツリー編集への追従: **`FileWatcher` 経由の変更通知を第一の契機とする**

### `.git/index` fingerprint の限界（重要）

`.git/index` の mtime は **素の作業ツリー編集では変化しない**。したがって fingerprint
ポーリングだけでは「編集して保存 → unstaged バッジが出る」を捉えられない。
fingerprint は *`git add` / commit / checkout など index を動かす操作の検出*と
*キャッシュの妥当性判定*に用途を限定し、作業ツリー編集の追従は `FileWatcher` に委ねる。

さらに `git status` は既定で index を refresh して mtime を書き換えうるため、
fingerprint ポーリングと素朴に組み合わせると
「status 実行 → fingerprint 変化 → 再取得 → …」の**自己励振ループ**になる。
これを避けるため status 実行には必ず `--no-optional-locks` を付ける。

### Phase 2 実装で採った形（2026-08-02）

ポーリングは一切行わない。契機は次の 2 つだけで、どちらもイベント駆動。

1. **`.git/index` の監視**（`SidebarNavigator` が状態取得のたびに対象を張り直す）
   — `add` / `commit` / `checkout` は index を置き換えるので拾える。`FileWatcher` は
   アトミック保存に追従するため親（`.git` ディレクトリ）も見ており、index の差し替えを
   取りこぼさない。監視対象パスは `GitStatusSnapshot.indexURL`（worktree では `.git` が
   ファイルなので呼び出し側では組み立てられない）を通じて渡す。
   通知は `.onlyIfIndexChanged` で受け、fingerprint が動いていなければ git を起こさない。
2. **表示中ファイルの再読込**（`ViewerStore.onContentReloaded`）
   — 作業ツリーの編集は index を動かさないため、1 では拾えない。既存の
   FileWatcher → 再読込の経路に相乗りするだけで済み、監視を追加しない。

ディレクトリ監視は追加していない。1・2 とウィンドウのキー化（Phase 1）で
受け入れ条件を満たせるため、監視対象を増やす理由がなかった。

## エラー処理・縮退

- git 不在 / 非リポジトリ / コマンド reject → status 無し（バッジ非表示）
- デフォルトブランチ検出不可 → branchModified のみ無効化し、
  staged / unstaged / untracked は表示を継続
- git 呼び出しは timeout（既存 `GitCommandRunner` 既定 10 秒）でハング防止

## フィーチャーゲート

<!-- derived-from ./2026-07-28-code-font-settings-design.md -->

`FeatureGate.inProgressFeaturesEnabled` を単一窓口として参照する。
ゲートは UserDefaults / 環境変数ではなく `#if DEBUG` とバージョン文字列（`-dev.N` 接尾辞）で
決まる。バッジ描画（および status 取得のトリガ）を
`if FeatureGate.inProgressFeaturesEnabled { ... }` で囲い、stable 昇格時に分岐を撤去する。
撤去タスクは task-187 として登録済み。

**`FeatureGate` は task-180 で実装済み**（`befold/App/FeatureGate.swift`）。当初の
ブロックは解消しており、Phase 1 から露出制御を接続してよい。
先行利用者だったコードフォント設定は task-184 で stable 昇格・ゲート撤去済みのため、
本機能が現時点で唯一の FeatureGate 利用者になる。

囲い方は撤去済みの先例（`MainMenuBuilder`）に倣い、**ロジックは常時ビルドし、
露出点だけを `if` 1 箇所で囲う**（撤去時にその 1 行を消すだけで済む形）。

## 段階的計画（フェーズ）

- **Phase 1**: `GitStatusReader` + `GitStatusStore`（porcelain v2 のみ）。
  staged / unstaged / untracked のバッジ表示。更新は refresh + フォーカス時。
- **Phase 2**: 作業ツリー編集への追従（`FileWatcher` 起点 + fingerprint による
  キャッシュ無効化）。
- **Phase 3**: merge-base + branch diff による「ブランチ内変更」バッジ（C の本体）。

各フェーズは独立してマージ可能。

**Phase 1 の API は同期のまま書く**（既存 `GitFileIndexing` / `GitCommandRunner` と揃える）。
task-226（`GitCommandRunner` の async 化 / `GitCommandFileIndex` の actor 化）は
着手条件に「Phase 2 に着手するとき」を挙げているため、Phase 2 の冒頭で再評価する。

## テスト

- `GitStatusReader`: 一時 Git リポジトリを作り、staged / unstaged / untracked /
  コミット済み変更の各状態で porcelain / diff パースを検証（`GitRepository` テストと同方式）。
  リポジトリ生成は `BefoldTestSupport/GitTestRepo` を単一情報源として使う。
  staged / unstaged / untracked / ブランチ分岐を作るヘルパーは現状不足しているため、
  Phase 1 で `GitTestRepo` 側に追加する（テストごとに `git` を直叩きしない）。
- 実 git を spawn するテストは `GitRepositoryIntegrationTests` と同じ扱いにする
  （`GitCommandRunnerResourceLeakTests` のリーク基準線にノイズを乗せるため、本数は絞る）。
- porcelain パースなど純関数部分は、実 git を起動せずフィクスチャ文字列で検証する。
- `GitFileStatus` → バッジ写像: 純粋関数としてユニットテスト
  （staged+unstaged 両立時の index 優先など）。
- デフォルトブランチ検出不可時の branchModified 無効化を検証。
- WebView / GUI 層のバッジ描画そのものは自動テスト対象外（リリース前手動チェック）。
