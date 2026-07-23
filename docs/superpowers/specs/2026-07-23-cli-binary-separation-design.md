# CLI バイナリ分離の設計

## 概要

現在 CLI と GUI が共有している単一バイナリ `befold` を、GUI アプリ (`befold`) と CLI ツール (`befold-cli`) の 2 つの executable に分離する。CLI は `befold.app/Contents/MacOS/befold-cli` に同梱し、`/usr/local/bin/befold` の symlink 先を変更する。

## 動機

現行の単一バイナリ設計では以下の問題がある:

- CLI プロセスが `NSApplication.run()` に入り GUI アプリ化してしまう（TASK-106 で `open -a` + ポーリング + forwarding のワークアラウンドで対処済みだが、根本解決ではない）
- CLI コンテキストで Sparkle updater が起動しエラーダイアログが表示される（TASK-107 で try/catch 抑止済みだが、そもそも CLI で Sparkle が動く必要がない）
- `AppDelegate.launch()` に CLI 分岐ロジック（転送・新規起動判定・`launchAppAndForward`）が混在し、GUI のエントリポイントが複雑化している

## ターゲット構成

```
Package.swift
  ├── BefoldKit (library)          # 既存: 純粋ロジック
  ├── BefoldRenderKit (library)    # 既存: WKWebView レンダリング
  ├── BefoldCLI (library, new)     # CLI 共通ロジック
  │     ├── CLIInstanceRouter      # 送信側（forward, runningInstance, waitForAck）
  │     ├── CLIOpenOptions         # 表示オプション Codable 構造体
  │     ├── CLICheckCommand        # --check ロジック
  │     ├── CLIBookmarkCommand     # --bookmark ロジック
  │     └── CLIInstaller           # shim インストール
  ├── befold (executable)          # GUI アプリ
  │     ├── AppDelegate            # NSApplication ライフサイクル（CLI 分岐なし）
  │     ├── CLIInstanceRouter 受信 # handleCLIOpenRequest, sendAck
  │     ├── CLIRequestDeduplicator # 重複リクエスト排除
  │     ├── CLIShimInspector       # shim 鮮度チェック
  │     └── CLIInstallUI           # メニューからのインストール UI
  └── befold-cli (executable, new) # CLI ツール
        ├── BefoldCLICommand       # @main, ArgumentParser エントリポイント
        └── CLIAppLauncher         # open -a + poll + forward ロジック
```

## CLI バイナリの振る舞い

```
befold-cli [flags] [paths...]
  ├── --check <paths>     → CLICheckCommand で判定、stdout に出力、exit
  ├── --bookmark <paths>  → CLIBookmarkCommand で登録、stdout に出力、exit
  ├── --version           → バージョン出力、exit
  ├── --help              → ヘルプ出力、exit
  └── <paths>             → ファイルオープン
        ├── 既存インスタンスあり → forward → exit(0)
        ├── 既存インスタンスなし → open -a befold.app → poll → forward → exit(0)
        └── パスなし            → open -a befold.app → exit(0)
```

CLI は一切 GUI 化しない。`NSApplication.run()` を呼ぶパスが存在しない。パスなし起動（`befold` だけ実行）も `open -a` で GUI を起動して exit する。

ArgumentParser の `commandName` は `"befold"` のままにし、ユーザーが叩くコマンド名に影響を与えない。

## ファイル移動と分割

### 移動先: `BefoldCLI/`（新規ライブラリ）

| ファイル | 移動元 | 内容 |
|----------|--------|------|
| `CLIInstanceRouter.swift` | `befold/App/` から送信側を抽出 | `runningInstance()`, `forward()`, `waitForAck()`, notification 名定数 |
| `CLIOpenOptions.swift` | `befold/App/` | 表示オプション構造体 |
| `CLICheckCommand.swift` | `CLISubcommandCommand.swift` から分割 | `--check` ロジック |
| `CLIBookmarkCommand.swift` | `CLISubcommandCommand.swift` から分割 | `--bookmark` ロジック |
| `CLIInstaller.swift` | `befold/App/` | symlink 作成ロジック |

### 新規: `befold-cli/`（CLI executable）

| ファイル | 内容 |
|----------|------|
| `BefoldCLICommand.swift` | `@main`, ArgumentParser パース、コマンドディスパッチ |
| `CLIAppLauncher.swift` | `open -a` + poll + forward + exit ロジック |

### GUI 側で削除

| ファイル | 理由 |
|----------|------|
| `BefoldRootCommand.swift` | CLI 側へ移動 |
| `CLISubcommandCommand.swift` | `BefoldCLI` ライブラリへ分割移動 |
| `CLIOpenOptions.swift` | `BefoldCLI` ライブラリへ移動 |

### GUI 側で残すもの（受信側）

| ファイル | 内容 |
|----------|------|
| `CLIInstanceRouter.swift` | 受信側のみ: `decode(userInfo:)`, `sendAck()`, `requestID(from:)` |
| `CLIRequestDeduplicator.swift` | 重複リクエスト排除 |
| `CLIShimInspector.swift` | shim 鮮度チェック |
| `CLIInstallUI.swift` | メニューからのインストール UI |

### CLIInstanceRouter の分割

notification 名やキー定数は `BefoldCLI` ライブラリ側に置き、GUI 側が `import BefoldCLI` して参照する。

- **送信側**（`BefoldCLI`）: `runningInstance()`, `forward()`, `waitForAck()`, notification 名・キー定数
- **受信側**（GUI `befold/App/`）: `decode(userInfo:)`, `sendAck()`, `requestID(from:)`, notification 登録

## GUI 起動フローの変更

### 分離後の GUI 起動フロー

```
befold (GUI バイナリ)
  NSApplicationMain → AppDelegate
    applicationWillFinishLaunching:
      ├── DocumentController 初期化
      ├── sessionRestorer.captureSavedState()
      └── handleCLIOpenRequest の notification 登録（既存通り）
    applicationDidFinishLaunching:
      ├── メニュー構築
      ├── セッション復元（前回のタブ構成）
      ├── Sparkle updater 起動
      └── CLI shim 鮮度チェック
```

### CLI からファイルを開く場合

```
befold-cli file.mmd
  → open -a befold.app（GUI が未起動なら起動される）
  → poll で GUI の起動を待つ
  → distributed notification で paths + options を転送
  → GUI: handleCLIOpenRequest → openPaths()
  → befold-cli: exit(0)
```

### 主な変更点

- GUI は常にセッション復元から起動する。「CLI から渡された初期パスでウィンドウを開く」パスは廃止し、全て `handleCLIOpenRequest` 経由に統一
- `initialPaths` / `initialOptions` プロパティは不要になる
- `applicationDidFinishLaunching` でのパス有無分岐が消え、常にセッション復元

### AppDelegate から削除するもの

- `static func main()` — `@main` は `NSApplicationMain` 相当に
- `static func launch(withInitialPaths:options:)` — 廃止
- `decideLaunchAction()`, `isTrivialActivateOnly()`, `launchAppAndForward()` — 全て削除
- `initialPaths`, `initialOptions` プロパティ — 不要

## テスト戦略

### 既存テストの影響

- `BefoldRootCommandIntegrationTests` — CLI バイナリのパスが `befold-cli` に変わるため、`builtExecutableURL()` の解決ロジックを更新
- `BefoldRootCommandTests`（ユニットテスト）— `BefoldRootCommand` が `BefoldCLI` モジュールに移動するため import 先を変更
- その他のテスト — GUI 側のロジックに変更がないものは影響なし

### 新規テスト

| テスト | 種別 | 内容 |
|--------|------|------|
| `CLIInstanceRouter` 送信側 | unit | `forward` の notification 発行・ACK 待機ロジック（モック可） |
| `CLIAppLauncher` | unit | `open -a` + poll + forward のフロー（Process を `ProcessLaunching` プロトコル + デフォルト引数で DI） |
| `befold-cli` 統合テスト | integration | 実バイナリで `--check`, `--version`, `--help` の出力と exit code を検証 |

### テストターゲット構成

```
befoldTests (既存)     — BefoldKit, BefoldRenderKit, befold (GUI) のテスト
befoldCLITests (新規)  — BefoldCLI ライブラリのユニットテスト
```

統合テストは `befoldTests` に残す（`builtExecutableURL()` で `befold-cli` バイナリを解決）。

### Process DI の解消

`CLIAppLauncher` は新規クラスなので、最初から `ProcessLaunching` プロトコル + デフォルト引数で設計する。今回の PR で見送った Process DI の課題が自然に解消する。

## shim 移行の互換性

### 移行シナリオ

ユーザーが既に `/usr/local/bin/befold` を使っている場合、アップデート後に shim が古い GUI バイナリを指したままになる。

### 対策

- `CLIShimInspector` の鮮度チェックを拡張する。現行は symlink 先が現在のバンドルのパスかを見ているが、加えて symlink 先のファイル名が `befold-cli` であることも検証する
- 旧 shim（`Contents/MacOS/befold` を指す symlink）は `staleSymlink` と判定され、既存の通知バナーで再インストールを案内
- `CLIInstaller.install()` の symlink 先を `Contents/MacOS/befold-cli` に変更

### ユーザー体験

- アップデート後の初回起動で「CLI コマンドを更新してください」の通知が出る
- メニューから「Install 'befold' command in PATH」を選ぶと新しい symlink に更新される
- 自動再インストールはしない（`/usr/local/bin/` への書き込みにはユーザー許可が必要なため、現行通り明示的な操作を求める）
