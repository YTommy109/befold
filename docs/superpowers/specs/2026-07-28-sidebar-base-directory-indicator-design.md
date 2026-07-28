# サイドバー基準ディレクトリ表示 設計

## 目的

「相対パスのコピー」と「Quick Open」がどのフォルダを基準にしているかを、
サイドバー上部に常時表示し、ユーザーがこれらの挙動を予測できるようにする。

現状、git ルート検出結果（`gitFileIndex.repositoryRoot(forFileAt:)`）は
挙動（相対パスコピーの基準・Quick Open のスコープ・参照解決）にのみ影響し、
UI 上に基準を示すシンボルは存在しない。本機能でこの基準を可視化する。

## 表示内容

サイドバー（`FileListView`）のヘッダー最上部に、1 行のインジケータを追加する。
構成は「アイコン ＋ フォルダ名 ＋ ツールチップ」の 2 要素。

| 状態 | アイコン | ラベル | 意味 |
| ---- | ------- | ------ | ---- |
| git ルート | git を想起させる SF Symbol（実装時に macOS 14 での可用性を確認） | git ルートのフォルダ名（例: `befold`） | 相対パス・Quick Open が git ルート基準 |
| 非 git（フォールバック） | `folder` | 基準ディレクトリ名（= `workspaceRoot`） | git 管理外。workspaceRoot 基準 |

- **ツールチップ**: 基準ディレクトリのフルパス ＋「Git リポジトリ」/「通常フォルダ」の区別。
- アイコンで「git 基準かどうか」、ラベルで「どのフォルダか」が一目で分かる。
- 本機能は **情報表示のみ**。クリック操作（パスコピー・Finder 表示等）は
  スコープ外とし、必要になれば後から追加する。

## データフロー

- **基準ディレクトリの算出**: `gitRoot ?? model.rootDirectory`。
  - git ルートは既存の `resolveGitRoot`（= `gitFileIndex.repositoryRoot(forFileAt:)`）を再利用。
  - これは `PathRelativizer.relativePath(of:workspaceRoot:gitRoot:)` の
    `gitRoot ?? workspaceRoot` と同一規則であり、表示と「相対パスコピー」挙動が一致する。
- **Quick Open の非 git フォールバックとの差異**: Quick Open は非 git 時に
  「開いているファイルの親ディレクトリ」を root にするため、`workspaceRoot` と
  異なる場合がある。ヘッダーはサイドバーが映す `rootDirectory`（= workspaceRoot）を
  基準に表示するのが安定的で自然。git 管理下（大多数のケース）では両者とも
  git ルートで完全一致する。この差はツールチップの説明でカバーする。
- 表示は現在アクティブなファイル URL の変化に追従し、`ViewerStore` / `FileListView`
  の既存の再描画経路に乗せる。

## 実装ポイント

1. **BefoldKit に純粋ロジックを追加**
   - 基準ディレクトリの名前・種別（`.gitRoot` / `.plainFolder`）・フルパスを
     算出する小さな値型（例: `BaseDirectoryDescriptor`）を新設する。
   - 入力は `gitRoot: URL?` と `workspaceRoot: URL`。`gitRoot ?? workspaceRoot` 規則で決定。
   - ユニットテスト対象。
2. **`FileListView` のヘッダーにビューを追加**
   - アイコン（種別で分岐）＋ フォルダ名 ＋ ツールチップ。既存ヘッダー構成に沿わせる。
3. **ローカライズ**
   - ツールチップ文言を `Localizable.xcstrings` に追加（「Git リポジトリ」「通常フォルダ」等）。
4. **SF Symbol の可用性確認**
   - git を想起させるアイコンが macOS 14 で使えるか実装時に検証。
     無ければ `folder` 系 + バッジや代替シンボルにフォールバックする。

## テスト

- **ユニット（BefoldTests）**: `BaseDirectoryDescriptor`
  - git ルートあり → 種別 `.gitRoot`・名前・フルパス。
  - git なし → `.plainFolder`・`workspaceRoot` の名前。
  - フォルダ名がボリューム直下等のエッジケースを確認。
- **GUI 層**: 自動テスト対象外（規約どおりリリース前手動チェック）。

## スコープ外

- クリック操作（基準パスのコピー、Finder 表示）。
- サイドバー非表示時の代替表示（ツールバー／タイトルバー等への露出）。
- git ブランチ名・変更状態など、基準ディレクトリ以外の git 情報の表示。
