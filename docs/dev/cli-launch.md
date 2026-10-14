# CLI 起動経路とワイヤプロトコル

<!-- derived-from ./native-app-design.md#モジュール構成 -->
<!-- constrained-by ../adr/0001-keep-appkit-app-lifecycle.md -->

本文書は `befold` コマンド実行から `befold.app` の起動/前面化・パス転送までの経路
と、CLI ↔ 本体アプリ間のワイヤプロトコルを解説する。

## ターゲット構成

CLI は 2 つのターゲットに分かれる。

| ターゲット | 位置 | 役割 |
|---|---|---|
| `befold-cli`（実行ファイル） | `BefoldApp/befold-cli/` | `BefoldCLIEntryPoint.run()` を呼ぶだけの薄い入口 |
| `BefoldCLI`（ライブラリ） | `BefoldApp/BefoldCLI/` | コマンド定義（ArgumentParser）と送信側の関心すべて（宛先探索・起動・再送・ACK 待ち・`--check` / `--bookmark`）。本体 GUI はリンクしない |

ワイヤ表現（`CLIRequest` / `CLIOpenOptions` / `CLIRequestWire`）は `BefoldKit` にあり、
送信側（`BefoldCLI`）と受信側（本体）の両方が参照する。本体 GUI の受信は
`BefoldApp/befold/App/AppCLIRequestReceiver.swift`。

**チャネルは Distributed Notification のみ**。XPC も URL scheme も argv 転送も
使っていない。

## 起動 → 前面化までの全経路

エントリポイントは `BefoldCLICommand`（`BefoldCLI/BefoldCLICommand.swift`、
`@main struct ... AsyncParsableCommand`、`commandName: "befold"`）。フラグは
`--check` / `--bookmark`、表示オプションは `@OptionGroup var openOptions:
OpenCLIOptions`、位置引数は `@Argument var paths: [String]`。

`--check` / `--bookmark` いずれも無ければ `run()` が
`CLIAppLauncher.launch(paths:options:)` を呼ぶ。

### 行を指定して開く（`--line`）

`--line <n>` は 1 つの文書の n 行目（1 始まり）をソース表示の先頭へ出す。

- **構文は `--line` のみ**。`path:LINE` は採らない: `:` を含むファイル名との曖昧さを
  CLI が実 FS を見て解く必要があり、得られるのは入力の短縮だけのため。
  Markdown の見出しアンカー指定も採らない（行番号で足り、レンダリング表示に
  行と DOM の対応が無い）。
- 検証（`validate()`）: 1 以上、パスはちょうど 1 つ、`--preview` / `--diff` と併用不可。
  表示モード未指定なら `OpenCLIOptions.cliOpenOptions` が `.source` にする
  （ワイヤには明示した `displayMode` が載る）。
- 本体側: `ViewerDocumentPresenter.applyCLIDisplay` が `ViewerStore.revealLineRequest`
  （`LineRevealRequest`。通し番号つき）を置き、`ViewerWebView.updateNSView` →
  `ViewerRenderer.reveal` が通し番号で一度だけ JS（`_mmdRevealLine`）へ渡す。
  配達は描画との前後を問わない: JS（`viewer-src/reveal-line.ts`）が文書パスつきで保留し、
  描画・追記・読み込み状態の変化のたびに満たせるか試す。
- 段階読み込み（1 チャンク ≒ 1000 行）の先にある行は、続きの読み込みを依頼して到着を待つ。
  **Swift は「末尾に達した」通知（`_mmdSetTruncated(false)`）を最後のチャンクの追記より先に送る**
  ため、依頼中の非切り詰め通知では確定せず、追記の後に判断する（実機で 2000 行目止まりに
  なった実例）。非切り詰め時の行数は Swift が 0 に正規化するので、行数は判断に使えない。
- 末尾を超える行・読み込み失敗は読めた範囲の末尾へ寄せる。画像・PDF など行を出せない
  種別では要求を捨てる。

### 表示オプションはパスを要する

`--source` / `--preview` / `--diff`、`--compare`、`--line-numbers` / `--no-line-numbers`、
`--sidebar` / `--no-sidebar`、`--sort`、`--line`、`--new-window` は「その文書をどう表示するか」の指定なので、
対象が無ければ適用先が無い。`BefoldCLICommand.validate()` が
`CLIOpenOptions.requiresPaths` を見て、次の 2 つをパース段階でエラーにする。

- パスを 1 つも渡していない
- ウィンドウを開かない `--check` / `--bookmark` と併用している

例外は `--hidden-files` / `--no-hidden-files` だけで、これはサイドバーの不可視ファイル
表示というアプリ全体設定のため対象を要さない。`requiresPaths` を
`options != CLIOpenOptions()` で代用してはならない（`--hidden-files` 単独まで弾く）。
`CLIAppLauncher` が使う `options == CLIOpenOptions()` は「そもそも GUI へ転送するか」の
別判定であり、目的が違う。

かつてはパス無しの表示オプションを、開いている全ウィンドウへ適用していた
（`ViewerWindowManager.applyDisplayOverrides`、TASK-82）。この経路だけが
表示モードの保存値を恒久的に書き換えていたため、TASK-413 で撤去した。

`CLIAppLauncher.run(...)`（`BefoldCLI/CLIAppLauncher.swift`）の判断ロジック:

1. paths を `standardizedFileURL.path` に正規化する
2. `CLIRequestForwarder.runningInstance()` で既存インスタンスを探す
3. **既存あり かつ paths 空・オプション既定** → `running.activate()` で純粋な
   前面化（転送なし）
4. **既存あり かつ 引数あり** → `CLIRequestForwarder.forward(...)` へ転送する
5. **既存なし** → `/usr/bin/open -a <bundlePath>` で起動する。bundlePath は
   `AppVersion.actualExecutablePath()` → `bundlePath(fromExecutablePath:)` で解決
6. 起動後、**paths 空・オプション既定なら転送せずそのまま終了（0）**。素の
   `befold` 実行では Distributed Notification は送られない
7. paths かオプションがある場合のみ、0.1s 間隔・10s タイムアウトで
   `runningInstance()` をポーリングし、出現したら `forward(...)` する
   （タイムアウトしたらエラーを出力して 1 を返す）

```mermaid
flowchart TD
  A["befold（paths…）実行<br/>BefoldCLICommand"] --> B{"--check / --bookmark?"}
  B -- "--check" --> C["CLICheckCommand<br/>（GUI 起動せず判定）"]
  B -- "--bookmark" --> D["CLIBookmarkRouter"]
  B -- なし --> E["CLIAppLauncher.run"]
  E --> F{"既存インスタンスあり?"}
  F -- "なし" --> G["/usr/bin/open -a<br/>で起動"]
  F -- "あり + 引数なし" --> H["running.activate()<br/>前面化のみ"]
  F -- "あり + 引数あり" --> I["CLIRequestForwarder.forward"]
  G --> G2{"paths か<br/>オプション指定あり?"}
  G2 -- "なし" --> G3["転送せず終了（0）"]
  G2 -- "あり" --> G4["ポーリングで<br/>起動待ち"]
  G4 --> I
  I --> J["Distributed Notification<br/>dev.befold.cli.openRequest"]
  J --> K["AppCLIRequestReceiver.handleRequest<br/>→ openPaths → NSApp.activate()"]
```

引数変換の境界は `OpenCLIOptions`（`BefoldCLI/OpenCLIOptions.swift`）。
ArgumentParser 依存の Flag を、`cliOpenOptions` プロパティで ArgumentParser 非依存
の `CLIOpenOptions`（BefoldCLI）へ変換する。3 値意味論（nil = 保存済み設定を維持）。

## ワイヤプロトコル

要求型 `CLIRequest`（`BefoldKit/CLIRequest.swift`）:

```swift
enum CLIRequest: Equatable, Codable, Sendable {
    case open(paths: [String], options: CLIOpenOptions)
    case bookmark(paths: [String])
}
```

`CLIOpenOptions`（`showHiddenFiles` / `sortOrder` / `showLineNumbers` /
`displayMode` / `comparisonTarget` / `showSidebar` / `line` と、非 Optional の `opensInNewWindow`）の
Codable 適合がワイヤ表現の唯一の情報源。

- 表示モードは `displayMode`（`rendered` / `source` / `diff`）。旧 CLI が送る
  `sourceMode: Bool` はデコード時に `displayMode` へ読み替える（`true` → `source`、
  `false` → `rendered`。両方あれば `displayMode` が勝つ）。送信側は旧キーを出力しない。
  逆に旧本体は `displayMode` を知らないため、`--diff` は旧本体では無視される
  （アップデート途中の一時的な組み合わせに限られるので許容している）。
- `opensInNewWindow` は旧 JSON にキーが無いので `decodeIfPresent ?? false`。
  受信側は `CLIOpenOptions.openDisposition` で `OpenDisposition.newWindow` に写し、
  `ViewerWindowOpenPolicy.reusableController` が既存の窓を再利用しない。
- `--compare` は `--diff` とセットでのみ指定できる（`validate()` が弾く）。単独指定を
  黙って捨てず、取り違えを知らせるための選択。比較基準は窓ごとのライブ値で、
  `--diff` だけなら窓の現在値を保つ。適用は `ViewerDocumentPresenter.applyCLIDisplay` の
  1 箇所（新規窓の init も既存窓への適用もここを通る）。

シリアライズ層 `CLIRequestWire`（`BefoldKit/CLIRequestWire.swift`）:

- 通知名: `requestNotificationName = "dev.befold.cli.openRequest"`、
  `ackNotificationName = "dev.befold.cli.openRequestAck"`
- `userInfo(for:requestID:)`: `CLIRequest` を JSONEncoder で JSON 文字列化し、
  `userInfo["request"]` / `["requestID"]` に載せる（Distributed Notification の
  userInfo は plist 表現限定のため JSON 文字列で包む）
- チャネル:
  `DistributedNotificationCenter.default().postNotificationName(..., deliverImmediately: true)`。
  宛先指定なしのブロードキャスト（単一 GUI インスタンスだけが受ける）

送信の駆動 `CLIRequestForwarder`（`BefoldCLI/CLIRequestForwarder.swift`）:

- `runningInstance()`: `NSRunningApplication.runningApplications(withBundleIdentifier:
  AppBundle.identifier)` から自プロセス以外を返す。`Bundle.main` ではなく
  `AppBundle.identifier`（`com.degino.befold`）を使う（symlink 起動で
  `Bundle.main` の bundleIdentifier が nil になるため）
- `postAwaitingAck(...)`: `UUID().uuidString` で requestID を採番し、AckWaiter を
  先に作ってから最大 `maxForwardAttempts = 20` 回 post、各回 `ackTimeout = 0.5s`
  待つ（総予算 10 秒）

## ACK 待ち（AckWaiting）

`AckWaiting` プロトコル / `DistributedAckWaiter`（`BefoldCLI/AckWaiting.swift`）。

- 役割: 転送要求が**実際に届いた確証**を得る。宛先プロセスの生存はオブザーバ
  未登録の可能性があり証拠にならないため、ACK 未観測なら失敗を返す（無言失敗の回避）
- `init(requestID:)` の時点で `ackNotificationName` のオブザーバを登録＝観測開始。
  post のたびに登録/解除しないのは、再送合間の ACK 取りこぼし窓を作らないため
- `wait(timeout:) async -> Bool`: 20ms 間隔で `Task.sleep` しつつ acked を確認。
  **必ず async**（async main コンテキストで `RunLoop.run` を同期に回すと Distributed
  Notification が配送されないため）

再送は GUI 側が requestID で重複排除するため、二重オープンにはならない。

## --check / --bookmark（フラグモード）

`befold` にサブコマンドは無い。`--check` / `--bookmark` はウィンドウを開かずに
結果だけを返すフラグで、同時指定や表示オプションとの併用は `validate()` が弾く。

**`--check`**（`BefoldCLI/CLICheckCommand.swift`）: GUI を起動せず、GUI と同じ
`SupportedFileResolver` / `ViewerLoadPipeline.load(...)` へ委譲して「開けるか」を
判定する（独自判定による GUI とのドリフト回避）。存在確認・フォルダ内解決・broken
symlink 判定・`FileType`・サイズ・拒否理由を `CLICommandResult` で返す。

**`--bookmark`**: 経路が 2 段。

- `CLIBookmarkRouter`（`BefoldCLI/CLIBookmarkRouter.swift`）: 起動中インスタンスが
  あれば `CLIRequestForwarder.forwardBookmark` で GUI に転送する（GUI を唯一の
  writer にして UserDefaults 配列の read-modify-write 競合を回避）。なければ
  `addLocally` で CLI が直書きする。転送失敗時はローカル書き込みへフォールバック
  しない（遅延到達による二重書き込み防止）
- `CLIBookmarkCommand`（`BefoldCLI/CLIBookmarkCommand.swift`）: 存在確認後に
  `addBookmark(url)` を呼び、成否を `CLICommandResult` に返す

## CLIInstaller が設置する shim

`CLIInstaller`（`befold/App/CLIInstaller.swift`）。shim の実体は**スクリプトでは
なく symlink**。`defaultInstallPath = /usr/local/bin/befold` を、
`<bundlePath>/Contents/MacOS/befold-cli` への symlink として設置する。

- symlink 方式の理由: スクリプトをコピーするとアプリ更新後も古いシムが残る。
  symlink はパス解決を OS に委ね、同一パスへ上書き更新される限り常に最新の実体を
  指す
- `writeDirectly`: 同一ディレクトリの一時パスに symlink を作り `rename(2)` で
  アトミック置換する（`FileManager` は symlink で不安定なため C の `rename` を直接
  使う）。失敗したら `writeWithAdministratorPrivileges`（`NSAppleScript` の
  `do shell script ... with administrator privileges`）にフォールバックする
- App Translocation 下では消える symlink を残さず失敗する

起動時に `AppDelegate.notifyIfCLIShimIsStale()` が `/usr/local/bin/befold` を
読み取り専用でチェックし、旧スクリプト実体や参照先不一致なら再インストールを
バナーで案内する（自動再設置はしない）。

## 受信側（本体アプリ）

`AppCLIRequestReceiver`（`befold/App/AppCLIRequestReceiver.swift`）は生成と同時に
Distributed Notification の `requestNotificationName` を購読する。`AppDelegate` の
`init` で eager に生成するのは、起動直後に届いた要求の ACK を取りこぼさないため。
`handleRequest(_:)` の流れ:

1. `CLIRequestWire.decode(userInfo:)` で `CLIRequest` を復元する
2. `requestID` があれば即 `CLIRequestWire.sendAck(requestID:)`（受信のたびに ACK）
3. `CLIRequestDeduplicator.shouldProcess(requestID:)` で requestID ごとに一度だけ
   実行する
4. `.open(paths, options)` → `onOpen`（`DocumentOpener.openPaths`）→ `NSApp.activate()`。
   `.bookmark(paths)` → `onBookmark`（前面化しない）

`DocumentOpener.openPaths(_:options:)` はパスを `openSequentially(_:options:)` へ渡して
個別ウィンドウに開く。paths が空になるのは `--hidden-files` 単独のときだけで、
その場合は操作対象の窓へ適用する。他の表示オプションは対象の文書を要するため CLI の
パース段階で弾かれる（上記「表示オプションはパスを要する」）。

## 終了コード

| コード | 意味 |
|---|---|
| 0 | 成功 |
| 1 | 失敗（`--check` / `--bookmark` で 1 つでも失敗、アプリの起動・転送に失敗） |
| 64 | 引数エラー（`EX_USAGE`。ArgumentParser が不明なオプションや `validate()` の違反に対して返す） |

64 は 2026-10-14 に `befold-cli` の実出力で測った値（`--bogus`・`--check`（パス無し）・
`--check --bookmark x`・`--check --source x` のいずれも 64）。
