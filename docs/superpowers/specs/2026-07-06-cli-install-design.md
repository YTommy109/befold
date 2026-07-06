# CLI Command Install Design

## Summary

VSCode の「シェルコマンドとしてインストールする」機能相当を befold に追加する。
App メニューから `/usr/local/bin/befold` にシムスクリプトをインストールし、
ターミナルから `befold <file>` / `befold <directory>` でファイル・フォルダーを開けるようにする。

## Requirements

- App メニューに「Install 'befold' command in PATH」項目を追加する
- 実行すると `/usr/local/bin/befold` にシムスクリプトをインストールする
- 書き込み権限がない場合は管理者権限プロンプト（AppleScript `with administrator privileges`）で昇格する
- 成功/失敗を `NSAlert` で通知する
- `befold <file>` で指定ファイルを開く（既存の `openViewer(for:)` フローをそのまま使う）
- `befold <directory>` で指定フォルダーを開く（**新規**：フォルダー内最初の対応ファイルを自動選択して開く）
- メニュー項目は常に「Install 'befold' command in PATH」固定表示（インストール済み判定によるラベル切り替えは行わない）
- アンインストールUIは今回のスコープ外

## Architecture

### メニュー統合

`MainMenuBuilder.makeAppMenuItem()`（`befold/App/MainMenuBuilder.swift:20-64`）の
「Check for Updates…」の直後に項目を追加する。

```
About
Check for Updates…
Install 'befold' command in PATH   ← 追加
─────────
Services ▶
...
```

- ローカライズキー: `menu.app.installCLI`（既存の `.l10n` バンドルパターンに従う）
- アクション: `AppDelegate.installCLI(_:)`（`checkForUpdates` と同じパターンで追加）

### CLI インストーラー

新規ファイル `befold/App/CLIInstaller.swift` に実装する。

```swift
enum CLIInstaller {
    static func install(bundlePath: String) -> Result<Void, CLIInstallError>
}

enum CLIInstallError: Error {
    case scriptWriteFailed(String)
}
```

- シムスクリプト内容:
  ```bash
  #!/bin/bash
  exec open -a "<Bundle.main.bundlePath>" "$@"
  ```
  `<Bundle.main.bundlePath>` はインストール実行時の `Bundle.main.bundlePath` をそのまま埋め込む。
- 書き込み手順:
  1. `/usr/local/bin/befold` への直接書き込みを試みる（`FileManager` でスクリプト文字列を書き込み、実行権限 `0755` を付与）
  2. 権限エラー（`EACCES` 等）の場合、`NSAppleScript` で
     `do shell script "..." with administrator privileges` を実行し、
     同じ内容を書き込む
- 呼び出し元 `AppDelegate.installCLI(_:)` が成否を受け取り、`NSAlert` で結果を表示する
  - 成功: 「`/usr/local/bin/befold` にインストールしました」
  - 失敗: エラー内容を表示

既知の制約: アプリを別の場所に移動した場合、シムスクリプトが古いパスを指すため再インストールが必要
（VSCode の `code` コマンドと同様の制約として許容する）。

### フォルダーオープン対応

現状 `AppDelegate.application(_:open:)` → `openViewer(for:)` はファイル専用で、
ディレクトリを渡すと `ViewerWindowController(fileURL:)` がディレクトリをファイルとして
扱おうとして壊れる（`AppDelegate.swift:84-88`, `ViewerWindowManager.swift:20-34`）。

`AppDelegate.openViewer(for:)` の入口に分岐を追加する:

```swift
func openViewer(for url: URL) {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

    if isDirectory.boolValue {
        guard let firstFile = DirectoryLister.firstSupportedFile(in: url) else {
            showAlert(message: String(localized: "cli.folder.noSupportedFile", bundle: .l10n))
            return
        }
        windowManager.openViewer(for: firstFile)
    } else {
        windowManager.openViewer(for: url)
    }
}
```

- `DirectoryLister.firstSupportedFile(in:)`（`Viewer/DirectoryLister.swift:74`、既存・テスト済み）をそのまま再利用する。
  これはフォルダーナビゲーション機能の「新しいウィンドウで開く」コンテキストメニューと同一のロジックであり、
  新規実装は不要。
- サイドバーは既存の仕組み（`ViewerWindowController.init` が `fileURL.deletingLastPathComponent()` から
  親ディレクトリを算出）により、開いたファイルの親＝指定フォルダーを起点に自動表示される。追加変更不要。
- 対応ファイルが1件もない場合はアラート表示のみでウィンドウを開かない。

<!-- constrained-by ./2026-07-06-folder-navigation-design.md#data-model -->

## Data Flow

```
1. ユーザーが App メニューから「Install 'befold' command in PATH」を選択
   → AppDelegate.installCLI(_:)
   → CLIInstaller.install(bundlePath: Bundle.main.bundlePath)
   → 直接書き込み、失敗時は管理者権限で書き込み
   → NSAlert で結果表示

2. ターミナルで `befold path/to/file.mmd`
   → シムスクリプトが `open -a <bundle path> path/to/file.mmd` を実行
   → NSApplication.application(_:open:) → AppDelegate.openViewer(for:)
   → ファイルとして既存フローで開く

3. ターミナルで `befold path/to/dir`
   → シムスクリプトが `open -a <bundle path> path/to/dir` を実行
   → AppDelegate.openViewer(for:) がディレクトリと判定
   → DirectoryLister.firstSupportedFile(in:) で最初の対応ファイルを取得
   → 見つかればそのファイルを既存フローで開く（サイドバーはフォルダー起点で自動表示）
   → 見つからなければアラート表示
```

## Testing

- ユニットテスト（`befoldTests/`, Swift Testing）:
  - `CLIInstaller` のシムスクリプト生成内容（bundle path が正しく埋め込まれるか）
  - `AppDelegate.openViewer(for:)` 相当のディレクトリ判定分岐（`DirectoryLister.firstSupportedFile(in:)` は既存テスト済みのため再テスト不要）
- 手動確認（リリース前チェック、WKWebView/OS権限系のため自動テスト対象外）:
  - メニューからインストール実行 → `/usr/local/bin/befold` が生成されることを確認
  - 書き込み権限がない状態での管理者権限プロンプト表示
  - ターミナルから `befold file.mmd` / `befold ~/somedir`（対応ファイルあり/なし双方）を実行して挙動確認

## Out of Scope

- アンインストール用メニュー項目・コマンド
- インストール済み状態の検知によるメニューラベルの動的切り替え
- `~/.local/bin` など他のインストール先の選択肢
- ディレクトリの再帰的探索（直下のみ対象、既存 `firstSupportedFile` の挙動に準拠）
