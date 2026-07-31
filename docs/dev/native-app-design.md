# befold — macOS ネイティブアプリ 設計ドキュメント

## 概要

befold は macOS 向けの Mermaid ダイアグラム・ビューアアプリである。

- `.mmd` / `.md` を中心に、SVG / HTML / CSV・TSV / 画像 / PDF / 各種ソースコードをプレビュー表示する
- ファイル変更を監視し、`WKWebView` 上のレンダリング結果をプロセス内でリアルタイム更新する
- HTTP サーバーやポート管理を持たない、プロセス内完結の構成
- 同じ描画エンジンを Finder の QuickLook 拡張でも共有する

本文書はアプリ全体の総覧・索引を担う。サブシステム別の詳細は次を参照:

- [ビューア描画データフロー](./viewer-rendering-dataflow.md) — ファイル種別ごとの描画差異と、監視 → Store → WebView → JS の一気通貫
- [テキスト読み込みデータフロー](./text-loading-dataflow.md) — Swift 側の読み込み（チャンク分割・エンコーディング・サイズ制限）
- [QuickLook 拡張の仕様と実現方法](./quicklook.md) — appex 構成・サンドボックス制約・描画エンジン共有
- [CLI 起動経路とワイヤプロトコル](./cli-launch.md) — `befold` コマンドから本体アプリへの起動・転送

---

## アーキテクチャ

```
befold.app (Swift 6 / AppKit + SwiftUI, macOS 14+)
  ├── AppDelegate                # ライフサイクル・メニュー・各コーディネータの束ね
  │     ├── ViewerWindowManager      # ウィンドウ生成・管理とセッション記録の更新
  │     ├── SessionRestorer          # 前回セッションのウィンドウ/タブ構成の保存・復元
  │     └── SPUStandardUpdaterController  # Sparkle アップデータの保持と起動
  ├── FileWatcher                # DispatchSource によるファイル監視（0.2s デバウンス）
  ├── ViewerStore                # @Observable 表示状態（content / rejectReason / isTruncated）
  ├── ViewerWebView               # WKWebView（NSViewRepresentable、ViewerRenderer を保持）
  └── Sparkle 2                   # 自動アップデート（appcast フィード経由）

BefoldQuickLook.appex (QuickLook 拡張)
  └── PreviewViewController        # ViewerRenderer を直接使い 1 回描画（詳細は quicklook.md）
```

描画エンジン `ViewerRenderer`（+ `viewer.html`）は `BefoldRenderKit` に切り出し、
本体アプリの `ViewerWebView` と QuickLook 拡張の双方から共有する。
コアロジックとレンダリングアセットは `BefoldKit` に置き、各ターゲットから参照する。

ファイル変更は `FileWatcher → ViewerStore → evaluateJavaScript` という
同一プロセス内の伝搬で反映する（詳細は
[ビューア描画データフロー](./viewer-rendering-dataflow.md#監視--store--webview--js-の一気通貫)）。

---

## モジュール構成

```
BefoldApp/
├── project.yml                # XcodeGen 定義（全ターゲットの単一定義元）
├── Package.swift               # SPM ビルド用
├── BefoldKit/                  # コアロジック＋レンダリングアセット（com.degino.befold.kit）
│   ├── ContentLoader.swift / ViewerLoadPipeline.swift  # 読込可否・種別分岐
│   ├── FileReading.swift / StringChunkReader.swift      # 読込抽象化・チャンク読み
│   ├── FileType.swift              # 拡張子→種別マッピングとレンダリング可否判定
│   ├── ViewerBridge.swift          # viewer.html との JS 関数名・メッセージ契約の集約
│   ├── RendererFeatures.swift      # 本体 / QuickLook の機能プリセット
│   ├── BundleAccessor.swift        # `Bundle.befoldKitResources`。SPM ビルドは
│   │                               # `.module`、Xcode ビルド（framework）は
│   │                               # `Bundle(for:)` を返し、両ビルドで Resources/ の
│   │                               # 解決先を一本化する
│   └── Resources/                  # viewer.html / viewer.js / viewer-main.js /
│                                    # mermaid / markdown-it / highlight.js / DOMPurify 等
├── BefoldRenderKit/            # 描画エンジン（本体 / QuickLook で共有）
│   └── ViewerRenderer.swift + ViewerRenderer+*.swift    # WKWebView ドライバ
├── befold/                     # 本体アプリ（com.degino.befold）
│   ├── App/                    # ライフサイクル・ウィンドウ管理・メニュー・各種永続化ストア
│   ├── Viewer/                 # ビューア本体（ViewerWebView・サイドバー・検索・ナビゲーション）
│   ├── FileWatching/           # FileWatcher, Debouncer
│   ├── Updates/                # UpdateChannel（Sparkle の appcast フィード切替）
│   └── Resources/               # AppIcon.icns, Localizable.xcstrings
├── BefoldQuickLook/            # QuickLook 拡張（app-extension、com.degino.befold.quicklook）
├── BefoldCLI/                  # CLI 共有ライブラリ（送受信両用のワイヤ表現・要求型）
├── befold-cli/                 # CLI 実行ファイル（befold コマンド。Contents/MacOS/befold-cli）
├── BefoldTestSupport/          # テスト共有ヘルパー
├── befoldTests/                # 本体・BefoldKit・BefoldRenderKit の Swift Testing テスト
│                               # （QuickLook 1 回描画・バッジ・機能プリセットもここ）
└── befoldCLITests/             # CLI の Swift Testing テスト
                                # （QuickLook 関連は拡張の Info.plist 検証のみ）
```

---

## App/ の主要コンポーネント

| コンポーネント | 責務 |
|---|---|
| `AppDelegate` | アプリライフサイクル全体の起点。各ストア・コーディネータの生成と保持 |
| `ViewerWindowManager` | ビューアウィンドウ（正規化パス → コントローラ）の生成・破棄、close/rename/key イベントに伴うセッション更新 |
| `SessionRestorer` | 前回セッションのウィンドウ/タブ構成のスナップショット保存と復元 |
| `SPUStandardUpdaterController` / `SPUUpdaterDelegate` | Sparkle アップデータの保持・起動と、チャンネル別 appcast フィード URL の供給（詳細は「自動アップデート」節） |
| `DocumentController` | `NSDocumentController` のサブクラス。Recent Documents からのオープンを `AppDelegate` に委譲 |
| `MainMenuBuilder` | メインメニューをコードで構築 |
| `RecentDocumentsStore` / `RecentDocumentsMenuController` | 最近使ったファイルを UserDefaults に自前で永続化しメニュー描画（ad-hoc 署名では OS 標準の Recent Documents が更新のたびにリセットされるため） |
| `SessionStore` | 終了時のウィンドウ/タブグループ構成（`SessionLayout`）の型 |
| `ScrollPositionStore` | ファイルごとのスクロール位置を永続化（レンダリング/ソース表示を別々に保存） |
| `ZoomStore` | ファイルごとのズーム倍率を永続化（0.5〜2.0、25% 刻み） |
| `SourceModeStore` | ファイルごとのソース/レンダリング表示モードを永続化 |
| `HiddenFilesPreference` | 不可視ファイル表示 ON/OFF をアプリ全体で永続化 |
| `FindOptionsPreference` | 検索の3トグル（大文字小文字区別・単語一致・正規表現）をアプリ全体で永続化 |
| `NavigationHistory` | タブごとの戻る/進む履歴スタック（非永続） |
| `SwipeHistoryNavigation` | トラックパッド水平スワイプから履歴移動方向を判定する純粋ロジック |
| `SidebarNavigator` | サイドバー選択・履歴からのファイル切替を仲介 |
| `CLIInstaller` | `/usr/local/bin/befold` に CLI 実行ファイルへの symlink を設置（詳細は [CLI 起動経路](./cli-launch.md#cliinstaller-が設置する-shim)） |
| `ViewerWindowController` | 1 ウィンドウ分のビューア制御（メニュー・ツールバー・WebView・サイドバーの統括） |
| `ViewerSplitViewController` | サイドバー＋コンテンツの `NSSplitViewController` |

---

## Viewer/ の主要コンポーネント

| コンポーネント | 責務 |
|---|---|
| `ViewerStore` | 表示状態（content・ファイル監視・削除検知）を保持する `@Observable` の中核モデル |
| `ViewerWebView` | `WKWebView` を包む `NSViewRepresentable`。Mermaid/Markdown 等をレンダリング。HTML ファイルは直接ロードも可 |
| `ViewerContentView` | ビューア本体の SwiftUI ビュー（ズーム・スクロール位置・検索設定・参照クリックの配線） |
| `FileListModel` / `FileListView` | サイドバーのファイル一覧・選択状態を管理する `@Observable` モデルと SwiftUI ビュー |
| `HistoryButtonView` | 戻る/進むツールバーボタン（クリックで移動、長押し/右クリックで履歴メニュー） |
| `MarkdownImageEmbedder` | Markdown 中のローカル画像を base64 data URI に埋め込む前処理（CSP 対応） |
| `ReferenceResolver` | クリックされた href/パス参照を外部 URL・ローカルファイル・非対応に分類 |
| `PathRelativizer` | パスコピー時に絶対パスを基準ディレクトリからの相対パスに変換 |
| `DirectoryLister` | サイドバー用のディレクトリ内ファイル/フォルダ一覧化 |
| `ViewerTheme` | キャンバス背景色の定義（ライト/ダーク、WebView との透過合わせ） |
| `WebViewProxy` | SwiftUI 内部生成の WKWebView を AppKit 側（メニューアクション）へ橋渡しする弱参照ホルダー |
| `SidebarTableViewLocator` | SwiftUI List の内部 NSTableView を取得するブリッジ |
| `UnsupportedFileView` | バイナリ等非対応ファイル用のプレースホルダービュー |

---

## ファイル監視

- `FileWatcher` は `DispatchSource.makeFileSystemObjectSource`（`.write` イベント）で
  ファイル本体とその親ディレクトリの両方を監視する
- エディタの atomic save（rename で inode が変わるケース）に追従できるよう、
  削除 → 再作成の検知と rename/move 追従（新パスへ監視を切り替え、`onRename` で通知）を行う
- シンボリックリンクは実パスに解決してから比較する
- イベント発生から既定 **0.2 秒のデバウンス**（`Debouncer`、`NSLock` で排他制御）後に読み込み・再描画する
- ファイル消失時はグレース期間後にウィンドウを閉じる。ゴミ箱への移動は削除として扱う

---

## 表示仕様

viewer.html・style.css・mermaid 初期化設定は BefoldKit の `Resources/` に同梱する。

- **mermaid 初期化**: `startOnLoad: false`、全ダイアグラム種別 `useMaxWidth: false`、`theme: 'default'`
- **`.mmd` の扱い**: 全文を `<pre class="mermaid">` に渡し mermaid.js に処理させる
- **`.md` の扱い**: markdown-it.js で markdown → HTML 変換する。
  ` ```mermaid ` フェンスは markdown-it のカスタムレンダラーで `<pre class="mermaid">` に出力し mermaid.js が SVG 描画する
- **その他ファイル種別**: SVG / HTML / CSV・TSV / 画像 / PDF / 各種ソースコードは
  `FileType` の判定に従い、ソースコードは highlight.min.js でシンタックスハイライトする
- **ズーム**: 0.5〜2.0（ボタン・キーは 25% 刻み、ホイールは連続）、基準スケール 0.75、
  `Cmd +/-`・`Ctrl + ホイール`・% 表示クリックでリセット。`ZoomStore` によりファイル単位で永続化
- **検索**: 大文字小文字区別・単語一致・正規表現の3トグル、次/前移動
- **ソース/レンダリング表示切替**: `SourceModeStore` でファイル単位に永続化。ソース表示時は行番号トグルを提供
- **戻る/進むナビゲーション**: タブごとの履歴（`NavigationHistory`）、ツールバーボタン・履歴メニュー・
  トラックパッドスワイプ（`SwipeHistoryNavigation`）に対応
- **エラーパネル**: `mermaid.parseError` で構文エラーの詳細メッセージを赤ボーダー・等幅フォントのパネルに表示
- **削除バナー**: ファイル削除時にグレーバナー＋背景色変更
- **サイドバー**: フォルダ/ファイル一覧、不可視ファイル表示トグル、ソート順、新規ウィンドウで開く操作を提供

---

## 自動アップデート

自動アップデートは **Sparkle 2**（`sparkle-project/Sparkle`）を用いる。`AppDelegate`
が `SPUStandardUpdaterController` を保持し、`SPUUpdaterDelegate` として appcast の
フィード URL を供給する。

| 要素 | 役割 |
|---|---|
| `SPUStandardUpdaterController` | Sparkle 標準のアップデータ本体（`AppDelegate` が `startingUpdater: false` で生成し、起動時に `updater.start()`） |
| `AppDelegate: SPUUpdaterDelegate` | `feedURLString(for:)` で現在のチャンネルの appcast URL を返す |
| `UpdateChannel`（`befold/Updates/`） | stable / develop の 2 チャンネル切替（UserDefaults）。チャンネルごとに appcast フィード URL を持つ |

appcast の実体と DMG は配布サイト（Cloudflare Worker）が GitHub をプロキシしつつ
アップデートチェックを計測する構成。ダウンロード・署名検証・インストール・再起動は
Sparkle が担当する。

> 補足: 以前は GitHub Releases API を用いた自前実装だったが、Sparkle 2 へ移行済み。
> ライフサイクル所有権と Sparkle 結合の背景は
> [ADR 0001](../adr/0001-keep-appkit-app-lifecycle.md) を参照。

---

## ファイル関連付け

Info.plist で以下を宣言する。

- `UTExportedTypeDeclarations`: 独自 UTI `com.degino.befold.mermaid-diagram`（拡張子 `mmd` / `mermaid`）、
  `com.degino.befold.source-code`
- `UTImportedTypeDeclarations`: `net.daringfireball.markdown`（`md` / `markdown`）をインポート
- `CFBundleDocumentTypes`: Mermaid（Owner）、Markdown（Alternate、iA Writer UTI 含む）、
  Source Code（多数の拡張子）、CSV/TSV、HTML をビューアとして登録

---

## 技術スタック

| 技術 | 用途 |
|---|---|
| Swift 6 / SwiftUI + AppKit | アプリ本体（macOS 14+、Strict Concurrency complete） |
| WKWebView | markdown・mermaid・各種ファイルのレンダリング |
| mermaid.min.js（同梱） | Mermaid SVG レンダリング |
| markdown-it.min.js（同梱） | `.md` ファイルの markdown → HTML 変換 |
| highlight.min.js（同梱） | ソースコードのシンタックスハイライト |
| dompurify.min.js（同梱） | markdown → HTML 変換結果のサニタイズ |
| github-markdown.css / github.css / github-dark.css（同梱） | Markdown 本文とコードハイライトのテーマ |
| Sparkle 2（SPM 依存） | 自動アップデート（appcast 取得・署名検証・インストール） |
| swift-argument-parser（SPM 依存） | `befold-cli` の引数解析 |
| XcodeGen | `.xcodeproj` 生成（`project.yml` が単一の定義元） |
| Swift Package Manager | ビルド（`BefoldKit` / `BefoldRenderKit` / `BefoldCLI` / `befold` / `befold-cli` / `BefoldTestSupport` / `befoldTests` / `befoldCLITests` の 8 ターゲット） |
| SwiftLint / SwiftFormat | ビルドプラグインとして実行 |
| Swift Testing | ユニットテスト |

---

## テスト方針

「ロジックは厚く、GUI/OS 層は薄く」の方針を採る。

- **ユニットテスト（Swift Testing）**: FileWatcher（デバウンス・atomic save・シンボリックリンク・
  削除検知）、Debouncer、ViewerStore の状態遷移、`UpdateChannel`（`Updates/` はこの 1
  ファイルのみ。Sparkle 本体の挙動は自動テスト対象外）、App/ 配下の各種永続化ストアなど、
  ロジック層は `befoldTests/` で網羅する
- **WebView 連携**: viewer.html の JS（ズーム・検索・エラーパネル）は `WKWebView` と
  Swift Testing を組み合わせて検証する
- **GUI/OS 層**（メニュー・State Restoration・ウィンドウ管理の見た目）は自動テスト対象外とし、
  リリース前の手動チェックリストで担保する

---

## スコープ外

- Windows / Linux 対応
- mermaid 以外のダイアグラム形式のネイティブレンダリング拡張
- エクスポート機能（SVG / PNG）
- テキスト編集機能（ビューア専用アプリ）
- AI 編集機能
