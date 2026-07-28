# サイドバー Git ステータス表示 設計

<!-- blocked-by ./2026-07-28-code-font-settings-design.md -->

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
具体的な色トークンとアクセント表現は実装時に既存 UI のカラーに合わせて決める。

バッジ非表示となるのは: 非 Git リポジトリ / git 不在 / status 取得失敗 / 変更なし。

## アーキテクチャ

### GitStatusReading / GitStatusReader（新規）

<!-- constrained-by #背景 -->

`GitCommandRunner` を用いてリポジトリルート単位で status を取得する。

```
protocol GitStatusReading: Sendable {
    // ルート配下の変更ファイルを status 付きで返す
    func status(forRepositoryAt root: URL) -> GitStatusSnapshot?
}
```

`GitStatusReader` の実装が呼ぶ git コマンド:

- `git status --porcelain=v2 -z`
  → 各パスの XY コード（X=index 側, Y=worktree 側）から staged / unstaged / untracked を判別
- デフォルトブランチ検出: `git symbolic-ref --short refs/remotes/origin/HEAD`
  （無ければローカル既定 main/master を試行）。検出不可なら branch 差分はスキップ。
- `git merge-base HEAD <default>` → base コミット
- `git diff --name-status -z <mergeBase> HEAD`
  → ブランチ内でコミット済みの変更ファイル（branchModified）

すべて `GitCommandRunner.hardeningOptions` を通し、`GitCommandOutcome.rejected/.unavailable`
は「status 無し」に縮退する。ワークツリー / submodule の `.git` 参照解決は既存
`GitRepository.gitDirectory(at:)` の方針を踏襲。

### GitFileStatus（新規）

各ファイルの状態を表す値型。`OptionSet` で staged / unstaged / untracked / branchModified の
組み合わせを表現し、表示層で「バッジ文字 + 色」へ写像する（写像は表示側の純粋関数）。

### GitStatusSnapshot（新規）

1 リポジトリルート分の `[URL: GitFileStatus]` マップ + 取得時点の
`.git/index` fingerprint（`GitRepository.indexFingerprint(at:)` 由来）。

### GitStatusStore（新規、@MainActor @Observable）

`GitCommandFileIndex` と同様に、リポジトリルート単位で `GitStatusSnapshot` を
LRU キャッシュし、全ウィンドウで共有する。重い git 呼び出しはバックグラウンドで
直列実行（既存 `GitCommandFileIndex` の `NSLock` 直列化パターンを踏襲）し、
結果を MainActor に反映する。`.git/index` fingerprint 変化でスナップショットを無効化。

Git 無効時のフォールバックとして `DisabledGitFileIndex` に相当する
no-op 実装（常に nil を返す）を既定値に用意する。

### FileListModel / FileListEntryRow（既存を拡張）

- `FileListModel` に `url -> GitFileStatus` の参照手段を持たせる
  （`GitStatusStore` から現ディレクトリ分を引く）。
- `FileListEntryRow` の `.file`（必要なら `.folder`）分岐に status バッジを追加描画。

### SidebarNavigator（既存を拡張）

`refreshFileList` の後段で `GitStatusStore` に現ディレクトリの status を問い合わせ、
`FileListModel` に反映する。

## データフロー

```
SidebarNavigator.refreshFileList
  → GitStatusStore.status(forDirectory:)   （ルート解決 + キャッシュ or git 実行）
  → FileListModel に url→GitFileStatus を反映
  → FileListEntryRow が右端に 1 文字バッジ + 色を描画
```

## 更新契機

1. サイドバー refresh 時（ディレクトリ移動・初回表示）
2. ウィンドウがキー化した時（フォーカス復帰）
3. `.git/index` fingerprint 変化のポーリング（既存 fingerprint を流用、数秒間隔）
   + 表示中ファイル保存時（既存 `FileWatcher` 経由の変更通知）

## エラー処理・縮退

- git 不在 / 非リポジトリ / コマンド reject → status 無し（バッジ非表示）
- デフォルトブランチ検出不可 → branchModified のみ無効化し、
  staged / unstaged / untracked は表示を継続
- git 呼び出しは timeout（既存 `GitCommandRunner` 既定 10 秒）でハング防止

## フィーチャーゲート

<!-- blocked-by ./2026-07-28-code-font-settings-design.md -->

`FeatureGate.inProgressFeaturesEnabled`（task-180 で導入予定）を単一窓口として参照する。
ゲートは UserDefaults / 環境変数ではなく `#if DEBUG` とバージョン文字列（`-dev.N` 接尾辞）で
決まる。バッジ描画（および status 取得のトリガ）を
`if FeatureGate.inProgressFeaturesEnabled { ... }` で囲い、stable 昇格時に分岐を撤去する
撤去タスクを backlog に登録する。

**依存**: `FeatureGate` は未実装のため、本機能の露出制御は task-180 の実装完了に
ブロックされる。それまでは Phase 1〜3 のロジック（`GitStatusReader` / `GitStatusStore` /
バッジ描画）を実装しつつ、露出点だけはゲート導入後に接続する。

## 段階的計画（フェーズ）

- **Phase 1**: `GitStatusReader` + `GitStatusStore`（porcelain v2 のみ）。
  staged / unstaged / untracked のバッジ表示。更新は refresh + フォーカス時。
- **Phase 2**: `.git/index` fingerprint ポーリングによる自動更新。作業ツリー編集への追従。
- **Phase 3**: merge-base + branch diff による「ブランチ内変更」バッジ（C の本体）。

各フェーズは独立してマージ可能。フィーチャーゲート露出は task-180 完了後に接続する。

## テスト

- `GitStatusReader`: 一時 Git リポジトリを作り、staged / unstaged / untracked /
  コミット済み変更の各状態で porcelain / diff パースを検証（`GitRepository` テストと同方式）。
- `GitFileStatus` → バッジ写像: 純粋関数としてユニットテスト
  （staged+unstaged 両立時の index 優先など）。
- デフォルトブランチ検出不可時の branchModified 無効化を検証。
- WebView / GUI 層のバッジ描画そのものは自動テスト対象外（リリース前手動チェック）。
