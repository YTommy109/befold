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

```text
befold.app (Swift 6 / AppKit + SwiftUI, macOS 14+)
  ├── AppDelegate                # ライフサイクルと @objc アクションの受け口（配線のみ）
  │     ├── AppStores                # アプリ全体で共有するストア・表示設定の束
  │     ├── ViewerWindowManager      # ウィンドウ生成・管理とセッション記録の更新
  │     │     ├── GlobalDisplayBroadcaster   # アプリの好み（ブックマーク・フォント）を全ウィンドウへ配る
  │     │     └── RecentRepositoryRecorder   # 「最近使ったリポジトリ」の記録とタブ構成の更新
  │     ├── SessionRestorer          # 前回セッションのウィンドウ/タブ構成の保存・復元
  │     ├── DocumentOpener           # URL をビューアで開く唯一の入口（逐次化・解決・選択パネル）
  │     ├── MainMenuCoordinator      # メインメニュー構築と動的メニューへのデータ供給
  │     ├── QuickOpenCoordinator     # Quick Open パネルの保持と候補源の組み立て
  │     ├── AppCLIRequestReceiver    # 別プロセスの CLI 要求の受信・ACK・重複排除
  │     ├── CLIShimCoordinator       # CLI シムの陳腐化チェックと設置
  │     └── AppUpdaterController     # Sparkle アップデータの保持と起動
  ├── FileWatcher                # DispatchSource によるファイル監視（0.2s デバウンス）
  ├── ViewerStore                # @Observable 対象ファイル・表示モード・監視の保持
  ├── ViewerContentState         # 読み込みが確定させた表示状態（content / fileType / rejectReason / isTruncated）
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

```text
BefoldApp/
├── project.yml                # XcodeGen 定義（全ターゲットの単一定義元）
├── Package.swift               # SPM ビルド用
├── viewer-src/                 # viewer 用 JS のモジュールソース（ESM）。
│                               # index.js をエントリに esbuild で
│                               # BefoldKit/Resources/viewer-bundle.js を生成する
├── BefoldKit/                  # コアロジック＋レンダリングアセット（com.degino.befold.kit）
│   ├── ContentLoader.swift / ViewerLoadPipeline.swift  # 読込可否・種別分岐
│   ├── FileReading.swift / StringChunkReader.swift      # 読込抽象化・チャンク読み
│   ├── FileType.swift              # 拡張子→種別マッピングとレンダリング可否判定
│   ├── ViewerBridge.swift          # Swift → JS（関数名・注入スクリプトの組み立て）
│   ├── ViewerBridgeMessage.swift   # JS → Swift（メッセージ名・ペイロードキーの契約）
│   │                               # （`referenceContextMenu` 等のブリッジメッセージ名はここ）
│   ├── ViewerDiffBridge.swift      # git 差分の JS 呼び出し（setDiff / setDiffLayout）
│   ├── OpenDisposition.swift       # 修飾キー→「開き方」(現在タブ/新規タブ/新規ウィンドウ)の対応表。
│   │                               # JS ブリッジ経由のクリック・直接 HTML モードの
│   │                               # decidePolicyFor・サイドバーの行クリック / ⌘Return が
│   │                               # 共通で通る単一の解釈元
│   ├── RendererFeatures.swift      # 本体 / QuickLook の機能プリセット
│   ├── BundleAccessor.swift        # `Bundle.befoldKitResources`。SPM ビルドは
│   │                               # `.module`、Xcode ビルド（framework）は
│   │                               # `Bundle(for:)` を返し、両ビルドで Resources/ の
│   │                               # 解決先を一本化する
│   └── Resources/                  # viewer.html / viewer-bundle.js（viewer-src/ から
│                                    # esbuild でビルドした成果物。コミット済み）/
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
├── BefoldCLI/                  # CLI 本体（コマンド定義・起動・要求転送・ワイヤ表現）
├── befold-cli/                 # CLI 実行ファイル（befold コマンド。Contents/MacOS/befold-cli）
│                               # 中身は BefoldCLIEntryPoint を呼ぶだけの薄い入口
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
| `AppDelegate` | アプリライフサイクルの起点と、メニュー/レスポンダチェーンから呼ばれる `@objc` アクションの受け口。依存の合成と各コーディネータへの転送だけを行い、実装は持たない |
| `AppStores` | アプリ全体で 1 個ずつ持つ永続化ストアと表示設定の束。束ねた 1 個を配ることで「全体で共有」を構造として保つ |
| `ActiveViewerProvider` | 「いま操作対象のビューアウィンドウ」を引く手続きの定義点（Quick Open パネル表示中も `NSApp.mainWindow` が元ウィンドウを指す前提をここだけに置く） |
| `DocumentOpener` | URL をビューアウィンドウで開く唯一の入口。逐次化・実 FS 解決・ファイル選択パネル・解決失敗時のアラート |
| `MainMenuCoordinator` | メインメニューの組み立てと、Recent / Bookmarks / 最近使ったリポジトリへのデータ供給（各 `NSMenuDelegate` の保持） |
| `QuickOpenCoordinator` | Quick Open パネルの保持、候補源（`AppQuickOpenEnvironment`）の組み立て、決定先を開く |
| `AppCLIRequestReceiver` | 別プロセスの CLI 起動から転送された要求の受信。ACK 返送と `requestID` 単位の重複排除。**生成と同時に購読するため `AppDelegate.init` で eager に作る** |
| `CLIShimCoordinator` | `/usr/local/bin/befold` の陳腐化チェックと設置、結果案内 |
| `ViewerWindowManager` | ビューアウィンドウ（正規化パス → コントローラ）の生成・破棄、close/rename/key イベントに伴うセッション更新 |
| `GlobalDisplayBroadcaster` | アプリ全体で 1 つの表示設定（ブックマーク・コードフォント）を開いている全ウィンドウへ配る。窓ごとのライブ値と窓の状態（ADR 0002）は扱わず、`SidebarDisplayDefaults` も `ZoomStore` も型として持たない |
| `RecentRepositoryRecorder` | 「最近使ったリポジトリ」への記録。git ルート/ラベルの解決は detached タスクで行い、反映のみ MainActor へ戻す |
| `ViewerTabGrouping` | タブグループ規則（結合・タブ構成スナップショットの組み立て・Space からはぐれた窓の救出）。セッション保存/復元と最近使ったリポジトリが同じ解釈を共有する単一の置き場 |
| `ViewerDisplayOptionsApplier` | 既に開いているウィンドウへの CLI 表示オプション適用規則 |
| `SessionRestorer` | 前回セッションのウィンドウ/タブ構成のスナップショット保存と復元 |
| `AppUpdaterController` | Sparkle アップデータの保持・起動と、チャンネル別 appcast フィード URL の供給（`SPUUpdaterDelegate` 準拠。詳細は「自動アップデート」節） |
| `DocumentController` | `NSDocumentController` のサブクラス。Recent Documents からのオープンを `AppDelegate` に委譲 |
| `MainMenuBuilder` | メインメニューをコードで構築 |
| `MenuShortcutCatalog` / `HelpShortcutSections` | Help > キーボードショートカット に並べる一覧の組み立て。メニュー由来は `NSMenu` から抽出し、メニューを経由しない操作は `ViewerShortcutCatalog` / `SidebarShortcutCatalog` / `QuickOpenShortcutCatalog` から引く。キー表記の組み立ては `ShortcutKey` に集約し、一覧と実装のずれは各カタログの突合テストで落とす |
| `RecentDocumentsStore` / `RecentDocumentsMenuController` | 最近使ったファイルを UserDefaults に自前で永続化しメニュー描画（ad-hoc 署名では OS 標準の Recent Documents が更新のたびにリセットされるため） |
| `SessionStore` | 終了時のウィンドウ/タブグループ構成（`SessionLayout`）の型 |
| `ScrollPositionStore` | ファイルごとのスクロール位置を永続化（レンダリング/ソース表示を別々に保存） |
| `ZoomStore` | ファイルごとのズーム倍率を永続化（0.5〜2.0、25% 刻み） |
| `DisplayModeStore` | ファイルごとの表示モード（レンダリング/ソース/差分）を永続化。旧キー `ViewerSourceModes` の Bool 辞書から 1 度だけ移行する |
| `SidebarDisplayDefaults` | サイドバー表示 4 値（表示形式・不可視ファイル・変更ファイルのみ・並び順）の**新規ウィンドウの初期値**をアプリ全体で永続化。ライブ値は窓ごと（ADR 0002「窓の状態」）で、窓は初期値の `SidebarDisplaySettings`（値型）と書き戻し用の `SidebarDisplayDefaultsRecording`（読み取りを持たない）だけを受け取る |
| `FindOptionsPreference` | 検索の3トグル（大文字小文字区別・単語一致・正規表現）をアプリ全体で永続化 |
| `NavigationHistory` | タブごとの戻る/進む履歴スタック（非永続） |
| `SwipeHistoryNavigation` | トラックパッド水平スワイプから履歴移動方向を判定する純粋ロジック |
| `SidebarNavigator` | サイドバー選択・履歴からのファイル切替を仲介 |
| `CLIInstaller` | `/usr/local/bin/befold` に CLI 実行ファイルへの symlink を設置（詳細は [CLI 起動経路](./cli-launch.md#cliinstaller-が設置する-shim)） |
| `ViewerWindowController` | 1 ウィンドウ分のビューア制御（依存の保持と生成手順、および外から来る契機の受け口）。実処理は独立した協働オブジェクトへ出してある（下記）。手元に残る拡張は `+FileNavigation` 提示対象の移動 / `+MenuActions` メニュー・ツールバー由来の `@objc` アクションと validate / `+References` 参照のオープン / `+Capabilities` 能力導出の入力集め / `+SidebarHost`・`+Renderer`・`+WindowDelegate` 各プロトコル準拠 |
| `ViewerWindowAssembler` | ウィンドウ生成時の部品の組み立てと配線（分割ビュー・サイドバーナビゲータ・WebView コマンド・ストア購読・スワイプ監視）。工程の中身だけを持ち、順序制約は `ViewerWindowController.init` に残す |
| `ViewerDocumentPresenter` | 文書の状態（表示モード・倍率・スクロール位置）の遷移と提示開始の 3 契機（ADR 0002 段 1）。cmd+U の戻り先の記憶もここに閉じる |
| `ViewerDiffPresenter` | git 差分の非同期取得・世代管理・レイアウト設定。取得を登録した契機で `ViewerDiffContent.pending` を立て、着地で確定させる（確定差分を表示中の取り直しでは降格しない） |
| `ViewerDiffContent` | 差分取得の結果状態（`unavailable` / `pending` / `diff(String)`）。「未着」と「確定して差分なし」を型で区別する。未確定の間はレンダラ（`ContentUpdatePlanner`）がモード切替だけの再描画を見送って前の表示を残し、切替直後にプレーンなソース表示が一瞬見える中間状態を作らない（TASK-407） |
| `ViewerCapabilitiesFactory` | 提示状態から `ViewerCapabilities` を導出する純関数（ADR 0002 段 2）。どの入力を信じるかをここ 1 箇所に置く |
| `GitDiffAvailability` | 差分表示モードを選ばせてよいかを決める git 側の事実（可用性・そのファイルに差分として出せる変更があるか）。基準ディレクトリの種別と `SidebarGitStatus` から導く純粋な写像で、**確定した否定の事実（git 管理外／扱えないリポジトリ／変更なし・未追跡）でだけ選択不可にする**。未解決の間は選べるままにして初期表示での入れ替わりを 1 方向に限る |
| `ReferenceMenuPresenter` | 参照の右クリックメニューの項目定義・表示・実行（`@objc` アクションを含めて 1 型に閉じる） |
| `ViewerWindowChrome` | `NSWindow` そのものの生成・外観・タイトル追従・初期フレーム決定。窓を 1 枚しか知らず、文書の状態にも他の窓にも触れない（重なり判定は述語で受け取る） |
| `ViewerSplitViewController` | サイドバー＋コンテンツの `NSSplitViewController` |
| `ReferenceContextMenu` | ビューア本文のリンク/パス参照の ctrl+クリック(右クリック)で出す `NSMenu` の項目定義。並び・文言はサイドバーのコンテキストメニューと揃える |
| `GitCommandRunner` | git 実行を一元化する薄い `Process` ラッパ（無害化オプション前置・タイムアウト・プロセスグループ打ち切り）。git を呼ぶ全機能の共通土台 |
| `GitRepository` | ルート解決・追跡ファイル列挙・worktree 一覧・`.git/index` fingerprint の問い合わせ |
| `GitCommandFileIndex` | 追跡ファイル索引のキャッシュ。全ウィンドウ・Quick Open で 1 個を共有し `git ls-files` の重複実行を防ぐ |
| `WorktreeCatalog` | 本体リポジトリごとの worktree 一覧キャッシュ（「最近使ったリポジトリ」メニューの階層表示用） |
| `GitStatusReader` / `GitStatusStore` | `git status --porcelain=v2` によるファイル状態の取得と、リポジトリルート単位のキャッシュ（サイドバーの状態バッジの供給元） |
| `GitFolderStatus` | ファイル単位の状態から、フォルダー配下（再帰的）の変更有無を集約する純関数と値型（フォルダー行のバッジ用。git は呼ばない） |

---

## Viewer/ の主要コンポーネント

| コンポーネント | 責務 |
|---|---|
| `ViewerStore` | 対象ファイル・表示モード・ファイル監視・削除検知を保持する `@Observable` の中核モデル |
| `ViewerContentState` | 読み込みが確定させた表示状態（content / fileType / filePath / rejectReason / 段階読み込み）の単一情報源。`ViewerStore.contentState` が窓ごとに 1 つ持つ |
| `ShowLineNumbersSetting` | 行番号表示の設定（UserDefaults への永続化と CLI の起動限り上書き）。`ViewerStore` が窓ごとに 1 つ持つ |
| `ViewerWebView` | `WKWebView` を包む `NSViewRepresentable`。Mermaid/Markdown 等をレンダリング。HTML ファイルは直接ロードも可 |
| `ViewerContentView` | ビューア本体の SwiftUI ビュー（ズーム・スクロール位置・検索設定・参照クリックの配線） |
| `PreviewTarget` / `PreviewTargetResolver` | プレビュー領域が提示する対象（文書・フォルダー一覧・未確定）。導出は `FileListModel.previewTarget` の 1 箇所（[ADR 0002](../adr/0002-presentation-state-and-capabilities.md)） |
| `ViewerCapabilities` | 「いま何ができるか」を提示状態から導出する純粋な型。メニュー・ツールバー・コマンド実行はこれだけを見る |
| `DocumentRendering` | 表示中の文書へできること（倍率・検索・印刷・スクロール位置）を表す port。実装は `WebViewDocumentRenderer`（WKWebView + ViewerBridge の JS を閉じ込める adapter） |
| `FileListModel` / `FileListView` | サイドバーのファイル一覧・選択状態を管理する `@Observable` モデルと SwiftUI ビュー |
| `HistoryButtonView` | 戻る/進むツールバーボタン（クリックで移動、長押し/右クリックで履歴メニュー） |
| `MarkdownImageEmbedder` | Markdown 中のローカル画像を base64 data URI に埋め込む前処理（CSP 対応） |
| `ReferenceResolver` | クリックされた href/パス参照を外部 URL・ローカルファイル・非対応に分類 |
| `PathRelativizer` | パスコピー時に絶対パスを基準ディレクトリからの相対パスに変換 |
| `BaseDirectoryDescriptor` / `BaseDirectoryIndicator` | 相対パスコピーと Quick Open の基準フォルダ（`gitRoot ?? workspaceRoot`）と、その表示。種別は git ルート / 通常フォルダ / **git リポジトリだが befold では扱えない**（libgit2 が開けない partial clone・reftable 等）の 3 つで、3 つ目はツールチップで git 機能が無効であることだけを伝える（失敗理由の種別は出さない） |
| `DirectoryLister` | サイドバー用のディレクトリ内ファイル/フォルダ一覧化 |
| `ViewerTheme` | キャンバス背景色の定義（ライト/ダーク、WebView との透過合わせ） |
| `WebViewProxy` | SwiftUI 内部生成の WKWebView を AppKit 側（メニューアクション）へ橋渡しする弱参照ホルダー |
| `FileListEntryRow` | サイドバーとプレビュー内フォルダー一覧が共有する行表示（アイコン・名前・git 状態バッジ） |
| `GitStatusBadge` / `GitStatusBadgeView` | `GitFileStatus` / `GitFolderStatus` からバッジ文字・色への純粋な写像と、その描画。サイドバー行の右端に出す（ファイル行は変更種別の文字、フォルダー行は集約を示す `•`） |
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
  `FileType` の判定に従い、ソースコードは highlight.js でシンタックスハイライトする
- **ズーム**: 0.5〜2.0（ボタン・キーは 25% 刻み、ホイールは連続）、基準スケール 0.75、
  `Cmd +/-`・`Ctrl + ホイール`・% 表示クリックでリセット。`ZoomStore` によりファイル単位で永続化
- **検索**: 大文字小文字区別・単語一致・正規表現の3トグル、次/前移動
- **表示モード切替**: ツールバーの 3 択セグメント（レンダリング / ソース / 差分）と `⌘1`〜`⌘3`。
  `DisplayModeStore` でファイル単位に永続化する。差分レイアウト（上下/左右）は `⌘\\` とツールバーのトグルで切り替え、
  好みの設定としてアプリ全体で共有する（`DiffDisplayPreference`）。ソース相当の内容を出している間は
  行番号トグルを提供
- **戻る/進むナビゲーション**: タブごとの履歴（`NavigationHistory`）、ツールバーボタン・履歴メニュー・
  トラックパッドスワイプ（`SwipeHistoryNavigation`）に対応
- **エラーパネル**: `mermaid.parseError` で構文エラーの詳細メッセージを赤ボーダー・等幅フォントのパネルに表示
- **削除バナー**: ファイル削除時にグレーバナー＋背景色変更
- **キーボードショートカット一覧**: Help のパネルは実装から生成する（表をビューに持たない）。
  メニュー由来はメニュー定義、ビューア内スクロールは `viewer-src/keyboard.js`、サイドバーは
  `SidebarKeyAction`、Quick Open は `QuickOpenKeyAction` が情報源。一覧と実装のずれは
  双方向のテスト（載せたキーが実際に動く／動くキーは必ず載っている）と、
  JS 側は Swift のカタログをパースする jest テストで検出する。
  マウス・トラックパッド操作はこのパネルには載せない
- **サイドバー**: フォルダ/ファイル一覧、不可視ファイル表示トグル、ソート順、新規タブ / 新規ウィンドウで開く操作を提供。
  ファイル行はビューア内リンクと同じ `OpenDisposition` の対応表で開き分ける:
  ⌘クリック / ⌘Return は新規タブ、⌘⇧クリック / ⌘⇧Return は新規ウィンドウ
  （どちらも選択 = 表示中ファイルの不変条件を保つため選択は動かさない）、
  ⌃クリックはコンテキストメニュー。修飾なしは従来どおり現在のタブで差し替える。
  新規タブは、起点ウィンドウと同じタブグループに同じファイルのタブが既にあれば
  重複タブを作らずそのタブを選択する（別ウィンドウで開いているだけなら新規タブ）。
  新規ウィンドウは常に素通しで開く。この判定は開く経路の合流点
  `ViewerWindowManager.openViewer` にあり、ビューア内リンクやコンテキストメニュー
  経由の新規タブにも同じ抑止が効く。
  表示 4 値（表示形式 / 不可視ファイル / 変更ファイルのみ / 並び順）は**窓ごとのライブ値**で、
  真実の源は各窓の `FileListModel`。変更の唯一の入口は
  `SidebarListingCoordinator.applyDisplayChange(_:)` で、メニュー（⌃⌘H / ⌘⌃G / ⌃⌘T）・
  サイドバーヘッダーのボタン・CLI はすべてそこへ合流する。
  ツリー⇄リストの切り替えは開閉状態とカレントフォルダーを引き継ぐ:
  ツリー→リストで展開集合を温存したまま root を `SidebarExpansion` のスナップショットに
  記録し、選択ファイルの親フォルダーへカレントを移す。リスト→ツリーはカレントが
  root の配下なら root と展開を復元して選択までの経路を追加展開し、配下の外なら
  移動先を新しいルートにする（元へ引き戻さない）。この遷移方針は
  `SidebarLayoutTransition` が持ち、ライブ値の更新自体は上の入口を通る。
  展開状態とスナップショットはウィンドウ単位・メモリのみで永続化しない

---

## 自動アップデート

自動アップデートは **Sparkle 2**（`sparkle-project/Sparkle`）を用いる。`AppUpdaterController`
が `SPUStandardUpdaterController` を保持し、`SPUUpdaterDelegate` として appcast の
フィード URL を供給する。`updaterDelegate` は weak 参照のため、`AppDelegate` が
`AppUpdaterController` を strong に保持し続けることが生存条件になる。

| 要素 | 役割 |
|---|---|
| `SPUStandardUpdaterController` | Sparkle 標準のアップデータ本体（`AppUpdaterController` が `startingUpdater: false` で生成し、起動時に `start()`） |
| `AppUpdaterController: SPUUpdaterDelegate` | `feedURLString(for:)` で現在のチャンネルの appcast URL を返す |
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
| mermaid（npm 依存 → `mermaid.min.js` をコピーして同梱、遅延ロード） | Mermaid SVG レンダリング |
| markdown-it（npm 依存 → viewer-bundle.js に同梱） | `.md` ファイルの markdown → HTML 変換 |
| highlight.js（npm 依存 → viewer-bundle.js に同梱、common ビルド） | ソースコードのシンタックスハイライト |
| DOMPurify（npm 依存 → viewer-bundle.js に同梱） | markdown → HTML 変換結果のサニタイズ |
| github-markdown-css / highlight.js のテーマ CSS（npm 依存 → コピーして同梱） | Markdown 本文とコードハイライトのテーマ |
| Sparkle 2（SPM 依存） | 自動アップデート（appcast 取得・署名検証・インストール） |
| swift-argument-parser（SPM 依存） | CLI の引数解析（コマンド定義は `BefoldCLI` にある） |
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
