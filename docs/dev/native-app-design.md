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
  │     ├── ViewerWindowManager      # ウィンドウ生成・管理（正規化パス → コントローラ辞書）
  │     │     ├── ViewerWindowSessionSync    # 開閉・rename・キー化に伴うセッション/履歴/ブックマークの追随
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

### MainActor の外へ逃がす処理は `withBlockingWork` を通す

git サブプロセスの起動・`stat`・ディレクトリ列挙・ファイル読み込みのように
**同期的に長く塞ぐ**処理は、MainActor の外で実行する。その逃がし先は
`BefoldKit/BlockingWork.swift` の `withBlockingWork` に一本化してあり、
呼び出しごとに専用スレッドを立てて実行する。

`Task.detached` は使わない。Swift 並行の協調スレッドプールの上で走るため、
プール幅（= コア数）ぶんが同時に塞がるとプロセス全体の前進が止まる。症状は
「全スイート pass なのに `«unknown»` issue で run が exit 1」という、
失敗テスト名の出ない形で現れる（TASK-424 / TASK-427 / TASK-516 で 3 度再発した）。

破れないよう次の 2 つで担保する。

- `scripts/check-no-detached-blocking.sh`（pre-commit と CI）が
  Swift コード中の `Task.detached` を機械的に弾く
- CI の build-and-test が `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`（プール幅 1）でも
  全件を回す。1 本でも協調スレッドを塞げば決定的に落ちる

---

## モジュール構成

```text
BefoldApp/
├── project.yml                # XcodeGen 定義（全ターゲットの単一定義元）
├── Package.swift               # SPM ビルド用
├── viewer-src/                 # viewer 用 TypeScript のモジュールソース（ESM）。
│                               # index.ts をエントリに esbuild で
│                               # BefoldKit/Resources/viewer-bundle.js を生成する
│                               # （型検査は npm run typecheck:viewer が別途担当）
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
│   ├── ViewerRenderer.swift + ViewerRenderer+*.swift    # WKWebView ドライバ
│   └── RemoteLoadBlocker.swift # WKContentRuleList でリモート読み込みを遮断
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
| `ViewerWindowManager` | ビューアウィンドウ（正規化パス → コントローラ）の生成・破棄と辞書の保持。開閉に伴う記録の追随は持たず、`ViewerWindowSessionSync` へ委ねる |
| `ViewerWindowSessionSync` | close / rename / ファイル切替 / key イベントを受けての辞書のキー付け替えと、セッション・最近使った項目・ブックマークの追随。`ViewerWindowControllerDelegate` 準拠（辞書の書き換えはマネージャの `register` / `detach` を通す。窓を作らない関心なのでマネージャから分離した） |
| `GlobalDisplayBroadcaster` | アプリ全体で 1 つの表示設定（ブックマーク・コードフォント・CSV の数値表示）を開いている全ウィンドウへ配る。窓ごとのライブ値と窓の状態（ADR 0002）は扱わず、`SidebarDisplayDefaults` も `ZoomStore` も型として持たない |
| `RecentRepositoryRecorder` | 「最近使ったリポジトリ」への記録。git ルート/ラベルの解決は detached タスクで行い、反映のみ MainActor へ戻す |
| `ViewerTabGrouping` | タブグループ規則（結合・タブ構成スナップショットの組み立て・Window メニューを選択中タブだけに揃える・Space からはぐれた窓の救出）。セッション保存/復元と最近使ったリポジトリが同じ解釈を共有する単一の置き場 |
| `ViewerDisplayOptionsApplier` | 既に開いているウィンドウへの CLI 表示オプション適用規則 |
| `SessionRestorer` | 前回セッションのウィンドウ/タブ構成のスナップショット保存と復元 |
| `AppUpdaterController` | Sparkle アップデータの保持・起動と、チャンネル別 appcast フィード URL の供給（`SPUUpdaterDelegate` 準拠。詳細は「自動アップデート」節） |
| `DocumentController` | `NSDocumentController` のサブクラス。Recent Documents からのオープンを `AppDelegate` に委譲 |
| `MainMenuBuilder` | メインメニューをコードで構築 |
| `MenuShortcutCatalog` / `HelpShortcutSections` | Help > キーボードショートカット に並べる一覧の組み立て。メニュー由来は `NSMenu` から抽出し、メニューを経由しない操作は `ViewerShortcutCatalog` / `SidebarShortcutCatalog` / `QuickOpenShortcutCatalog` から引く。キー表記の組み立ては `ShortcutKey` に集約し、一覧と実装のずれは各カタログの突合テストで落とす。ビューア内の一覧は文書内ジャンプのゲート（`FeatureGate.isDocumentJumpEnabled`）を必須引数で受け取り、ゲート開でのみ Enter / ⇧Return のジャンプ移動を載せ、Esc の説明を「検索バーを閉じる」から「検索バー・ジャンプバーを閉じる」へ入れ替える |
| `RecentDocumentsStore` / `RecentDocumentsMenuController` | 最近使ったファイルを UserDefaults に自前で永続化しメニュー描画（ad-hoc 署名では OS 標準の Recent Documents が更新のたびにリセットされるため） |
| `SessionStore` | 終了時のウィンドウ/タブグループ構成（`SessionLayout`）の型 |
| `ZoomStore` | ファイルごとのズーム倍率を永続化（0.5〜2.0、25% 刻み） |
| `WindowPresentationMemory` | ファイルごとのスクロール位置（レンダリング/ソース別）・表示モード（レンダリング/ソース/差分）・回転角を、**その窓の生存期間だけ**記憶する。`UserDefaults` を型の依存として持たず、永続化できない。生成するのは `ViewerDocumentPresenter` の 1 箇所だけで、窓ごとに 1 個（TASK-565）。表は「記憶の種類」で並び、面（web / PDF）では分けない——どの面がどれを使うかは能力（`canRotate` 等）が決める（TASK-574.3）。**記憶へ位置が届く経路は両面とも「切替直前の pull」1 本**。かつて web 面だけが持っていたスクロールごとの継続通知は、位置を永続化していた頃の名残なので撤去した（`PresentationMemoryWriteDirectionTests` が復活を検知する） |
| `PathKeyedTable` | メモリ上の「正規化パス → 値」表。`PathKeyedDictionary`（永続）とキーの規約と rename 追従を揃えつつ、`UserDefaults` を持たない |
| `SidebarDisplayDefaults` | サイドバー表示 4 値（表示形式・不可視ファイル・変更ファイルのみ・並び順）の**新規ウィンドウの初期値**をアプリ全体で永続化。ライブ値は窓ごと（ADR 0002「窓の状態」）で、窓は初期値の `SidebarDisplaySettings`（値型）と書き戻し用の `SidebarDisplayDefaultsRecording`（読み取りを持たない）だけを受け取る |
| `FindOptionsPreference` | 検索の3トグル（大文字小文字区別・単語一致・正規表現）をアプリ全体で永続化 |
| `NavigationHistory` | タブごとの戻る/進む履歴スタック（非永続） |
| `SwipeHistoryNavigation` | トラックパッド水平スワイプから履歴移動方向を判定する純粋ロジック |
| `SidebarNavigator` | サイドバー選択・履歴からのファイル切替を仲介 |
| `CLIInstaller` | `/usr/local/bin/befold` に CLI 実行ファイルへの symlink を設置（詳細は [CLI 起動経路](./cli-launch.md#cliinstaller-が設置する-shim)） |
| `ViewerWindowController` | 1 ウィンドウ分のビューア制御（依存の保持と生成手順、および外から来る契機の受け口）。実処理は独立した協働オブジェクトへ出してある（下記）。手元に残る拡張は `+FileNavigation` 提示対象の移動 / `+MenuActions` メニュー・ツールバー由来の `@objc` アクションと validate / `+References` 参照のオープン / `+Capabilities` 能力導出の入力集め / `+SidebarHost`・`+Renderer`・`+WindowDelegate` 各プロトコル準拠 |
| `ViewerWindowAssembler` | ウィンドウ生成時の部品の組み立てと配線（分割ビュー・サイドバーナビゲータ・WebView コマンド・ストア購読・スワイプ監視）。工程の中身だけを持ち、順序制約は `ViewerWindowController.init` に残す |
| `ViewerDocumentPresenter` | 文書の状態（表示モード・倍率・スクロール位置）の遷移と提示開始の 3 契機（ADR 0002 段 1）。cmd+U の戻り先の記憶と、窓の生存期間だけの記憶（`WindowPresentationMemory`）の所有もここに閉じる |
| `ViewerDiffPresenter` | git 差分の非同期取得・世代管理・レイアウト設定。取得を登録した契機で `ViewerDiffContent.pending` を立て、着地で確定させる（確定差分を表示中の取り直しでは降格しない） |
| `ViewerDiffContent` | 差分取得の結果状態（`unavailable` / `pending` / `diff(String)`）。「未着」と「確定して差分なし」を型で区別する。未確定の間はレンダラ（`ContentUpdatePlanner`）がモード切替だけの再描画を見送って前の表示を残し、切替直後にプレーンなソース表示が一瞬見える中間状態を作らない（TASK-407） |
| `ViewerCapabilitiesFactory` | 提示状態から `ViewerCapabilities` を導出する純関数（ADR 0002 段 2）。どの入力を信じるかをここ 1 箇所に置く |
| `GitDiffAvailability` | 差分表示モードを選ばせてよいかを決める git 側の事実（可用性・そのファイルに差分として出せる変更があるか）。基準ディレクトリの種別と `SidebarGitStatus` から導く純粋な写像で、**確定した否定の事実（git 管理外／扱えないリポジトリ／変更なし・未追跡）でだけ選択不可にする**。未解決の間は選べるままにして初期表示での入れ替わりを 1 方向に限る。フォルダーが git 由来の機能を出してよいかの判定そのものは `BaseDirectoryDescriptor.allowsGitFeatures(_:)` にあり、サイドバーの「変更のあるファイルのみ」と共有する（TASK-537） |
| `ReferenceMenuPresenter` | 参照の右クリックメニューの項目定義・表示・実行（`@objc` アクションを含めて 1 型に閉じる） |
| `ViewerWindowChrome` | `NSWindow` そのものの生成・外観・タイトル追従・初期フレーム決定。窓を 1 枚しか知らず、文書の状態にも他の窓にも触れない（重なり判定は述語で受け取る） |
| `ViewerSplitViewController` | サイドバー＋コンテンツの `NSSplitViewController` |
| `ReferenceContextMenu` | ビューア本文のリンク/パス参照の ctrl+クリック(右クリック)で出す `NSMenu` の項目定義。並び・文言はサイドバーのコンテキストメニューと揃える |
| `GitCommandRunner` | git 実行を一元化する薄い `Process` ラッパ（無害化オプション前置・タイムアウト・プロセスグループ打ち切り）。git を呼ぶ全機能の共通土台 |
| `GitRepository` | ルート解決・追跡ファイル列挙・worktree 一覧・`.git/index` fingerprint の問い合わせ。`GitRepository+RemoteLink` の `remoteFileLink(forFileAt:)` が、サイドバーの「リンクをコピーする」向けに origin・HEAD ブランチ・リポジトリルート基準の相対パスを 1 回のリポジトリオープンで解決する（作れない条件はすべて nil へ畳む） |
| `RemoteForge` | リモートを Web で見せるホスティング（GitHub / GitLab / Bitbucket）。ホスト名の判定・メニューへ差し込む表示名・ファイルを指す URL の形式（`/blob/` ・ `/-/blob/` ・ `/src/`）をこの 1 型に集める。ブランチ名で指し permalink は作らない。自建て（GitHub Enterprise / self-managed GitLab）はホスト名で判別できないため対象外 |
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
| `ViewerContentView` | プレビュー領域の SwiftUI ビュー。フォルダー一覧とファイルの描画面の出し分けだけを持つ |
| `DocumentSurfaceStack` | 描画面への配線（倍率・スクロール位置・検索設定・参照クリック）と、非対応・読み込み中のオーバーレイ（スピナーの条件は `ViewerContentState.showsLoadingIndicator`。`FileType.rendersFromData` が true の種別＝PDF は `content` を使わないため、空判定だけだと見えている PDF の上に重なる）。**PDF だけを開いた窓では WKWebView を作らない**（生成の遅延であって破棄ではない。一度作った面は残す / TASK-564.7） |
| `PreviewTarget` / `PreviewTargetResolver` | プレビュー領域が提示する対象（文書・フォルダー一覧・未確定）。導出は `FileListModel.previewTarget` の 1 箇所（[ADR 0002](../adr/0002-presentation-state-and-capabilities.md)） |
| `ViewerCapabilities` | 「いま何ができるか」を提示状態から導出する純粋な型。メニュー・ツールバー・コマンド実行はこれだけを見る |
| `DocumentRendering` | 表示中の文書へできることを表す port。宛先の違いで 2 群に分かれる——`DocumentSurfaceOperating`（倍率・検索・印刷・スクロール位置。**いま描いている 1 枚**へ振り分ける）と `DocumentSurfaceSyncing`（フォント・CSV 表示設定・ジャンプ可否・リネーム追随。**すべての面**へ配る）。実装は 2 つ——`WebViewDocumentRenderer`（WKWebView + ViewerBridge の JS を閉じ込める adapter）と `PDFDocumentRenderer`（`PDFView` の倍率計算と印刷を閉じ込める adapter / ADR 0009） |
| `DocumentSurfaces` | 窓が持つ描画面の束（WKWebView と `PDFView` の 2 枚）と、命令をどの面へ届けるかの決定。宛先を決めるのはこの型の `operating(on:)` / `syncingAll` だけで、メニュー・ツールバー・コマンドは種別を見ない。判定は**描画が確定した種別**（`ViewerContentState.fileType`）で行い、提示予定の URL では行わない |
| `FileListModel` / `FileListView` | サイドバーのファイル一覧・選択状態を管理する `@Observable` モデルと SwiftUI ビュー |
| `HistoryButtonView` | 戻る/進むツールバーボタン（クリックで移動、長押し/右クリックで履歴メニュー） |
| `MarkdownImageEmbedder` | Markdown 記法 `![]()` と inline HTML の `<img src>` が指すローカル画像を base64 data URI に埋め込む前処理（CSP 対応） |
| `ReferenceResolver` | クリックされた href/パス参照を外部 URL・ローカルファイル・非対応に分類 |
| `PathRelativizer` | パスコピー時に絶対パスを基準ディレクトリからの相対パスに変換 |
| `BaseDirectoryDescriptor` / `BaseDirectoryIndicator` | 相対パスコピーと Quick Open の基準フォルダ（`gitRoot ?? workspaceRoot`）と、その表示。種別は git ルート / 通常フォルダ / **git リポジトリだが befold では扱えない**（libgit2 が開けない partial clone・reftable 等）の 3 つで、3 つ目はツールチップで git 機能が無効であることだけを伝える（失敗理由の種別は出さない） |
| `DirectoryLister` | サイドバー用のディレクトリ内ファイル/フォルダ一覧化 |
| `ViewerTheme` | キャンバス背景色の定義（ライト/ダーク、WebView との透過合わせ）。外部の HTML 文書だけは例外で、文書が canvas ごと所有するためこの色は使われない |
| `WebViewProxy` | SwiftUI 内部生成の WKWebView を AppKit 側（メニューアクション）へ橋渡しする弱参照ホルダー |
| `PDFViewProxy` | 同上の `PDFView` 版。面ごとに 1 つ持つ |
| `PDFPreviewView` | PDF の描画面。`ZoomingPDFView` を包む `NSViewRepresentable` で、`ViewerContentState.data` を `PDFDocument` にして `ZoomingPDFView.present(document:rotation:zoom:scrollFraction:)` へ渡すだけの薄い層。差し替えの順序をここには書かない（TASK-574.1） |
| `ZoomingPDFView` | `PDFView` のサブクラス。**この面への書き込みはすべてここを通る**（TASK-574.1）。文書の差し替え手順を `present(document:rotation:zoom:scrollFraction:)` が同期 1 本で持ち（文書 → 回転 → 倍率 → `layoutSubtreeIfNeeded()` → 位置）、保留状態を作らない。表示設定と一度きりの配線は `init` が済ませるので、未設定の面は存在できない。ピンチ（受け皿は `PDFMagnificationGesture`）と Ctrl+ホイールを倍率操作として受け、キーボードのスクロール（Space・↑↓・j/k・Shift 付き）を `PDFSurfaceLayout` の表で解決して滑らかに送る。倍率（1.0 = ページ全体が収まる）を面が覚え、リサイズのたびに `layout` で入れ直す（`autoScales` は使わない）。回転は `layout` を起こさないので、`rotate(byDegrees:)` が回した直後に同期で入れ直す（メインキューへ後回しにすると、切り替え時に続けて入る `initialZoom` を前のファイルの倍率で上書きする / TASK-572）。回した後は `CATransaction.flush()` で PDFKit にレイアウトを走らせ、そこで積まれたページレイヤーの `CAAnimation` を剥がす——剥がさないと、ページの矩形が回転前から回転後へ約 250ms かけて補間される過程が見える（TASK-576。この依存が壊れると補間が再び見え、`PDFSurfaceRotationTests.rotationLeavesNoLayerAnimations` が落ちる）。**`document` プロパティを override してはならない**——PDFKit がバックグラウンドから読むため、`@MainActor` 隔離の override は `SIGTRAP` で落ちる（TASK-567） |
| `PDFPageIndicatorModel` | PDF 面の「現在ページ / 総ページ数」。窓ごとに 1 個で、生成は `DocumentSurfaces` の 1 箇所だけ（`PDFFindModel` と同じ粒度・同じ置き場）。**面へは `PDFViewProxy` 越しに読むだけで何も書かない。** 値を溜めず、通知のたびに面から読み直すので、回転・倍率・文書の差し替えのどれでも次の通知で実態へ揃う。更新契機は `NSClipView` の bounds 変更と `.PDFViewDocumentChanged`——PDFKit の `.PDFViewPageChanged` は使わない（窓へ載せてもヘッドレスでは一度も飛ばず、`currentPage` も 0 のままでテストから測れない / TASK-578.1 の実測）。購読は `object: nil` で受けて発火時に同一性で絞る（スクロールビューは文書の差し替えで作り直されるため、インスタンスを固定すると無音で更新が止まる） |
| `PDFPageIndicator` | 現在ページを PDF の**左下**に重ねる常時表示。右上は回転と検索が排他で使っており、常時表示を足すと必ずどちらかと重なる。地は他のオーバーレイと同じ（`.regularMaterial` + `.separator` 枠）で、文字は `.secondary` に落とす。**総ページ数が 0 のときだけは自分で引っ込む**——「文書が無い」「面がまだ組み上がっていない」のどちらでも 0 になり、`1 / 0` を描いてしまうため |
| `PDFMagnificationGesture` | ピンチを**倍率の増分**へ直して届ける入力アダプタ。認識器（`NSMagnificationGestureRecognizer`）の所有と、開始からの累積値を前回からの増分へ直す帳簿を持つ。面から分けてあるのは、これが「面であること」と無関係だから——倍率の意味と上下限は `ZoomingPDFView` 側にあり、こちらは PDF も倍率も知らない（TASK-577）。ピンチを `magnify(with:)` のオーバーライドだけに頼らないのは、内側の `PDFScrollView` が消費して上まで来ないことがあるため（TASK-568） |
| `PDFRotationOverlay` | PDF の右上に重ねる回転コントロール。メニューには置かない（その面を見ているときにしか意味が無い操作なので、対象の隣に置く）。**検索バーを開いている間は出さない**（どちらも右上なので重なる） |
| `PDFFindOverlay` | PDF の右上に重ねる検索バー（TASK-570）。web 面の `#mmd-bar` と同じ並び（入力欄・トグル・件数・前後移動・閉じる）。**トグルは大文字小文字の区別だけで、web 面よりも数が少ない**——PDFKit の検索は `.caseInsensitive` / `.literal` / `.backwards` しか受けず、単語一致・正規表現に対応する引数が無い（SDK ヘッダ実測）。`PDFPage.selectionForRange:` と `NSRegularExpression` で自前に組めばページ内に限り実現できるが、非同期検索の経路を丸ごと置き換えることになるので採らない |
| `PDFFindModel` | PDF 面の検索の状態（窓ごとに 1 個。`DocumentSurfaces` が持つ）。PDFKit の `beginFindString` で非同期に検索する——同期の `findString` は初回に文書全体のテキスト抽出を行い、実測で 150 ページの PDF に 152.4ms かかる（約 9 フレームのブロック）。非同期版は 0.0ms で戻り、通知をメインスレッドへ返すので `@MainActor` に閉じたまま扱える。**面へは書き込まない**（ハイライトと移動は `ZoomingPDFView` のメソッド経由。書き込み口を 1 つに保つ / TASK-574.1）。届いた一致は中身が現在の検索語かで受け入れる——`cancelFindString` は即座に止まらず通知は文書ごとに飛ぶので、同じ文書で検索し直すと前の検索の一致が新しい購読へ届く |
| `PDFSurfaceActions` | PDF 面と窓のあいだの受け渡し（倍率の通知・回転の要求）を 1 つにまとめた値。View の注入クロージャを 3 つ以下に保つため |
| `PDFSurfaceLayout` | PDF の面のレイアウト規則の単一の情報源。**換算だけを持ち、面を変更しない**（TASK-574.1）。「倍率 1.0 = ページ全体が収まる状態」の定義、フィット倍率、表示位置（文書全体に対する 0…1）の取得、スクロール余地、回転角の正規化、現在ページの索引（`currentPageIndex(of:)` / 定義は「面の中心より上端が上にあるページのうち最後のもの」。ページ間に余白があるので「中心を含むページ」だと該当なしになる。スクロール中に毎フレーム走るので二分探索する / TASK-578.1）、キーボードスクロールの割り当てと送り量（`keyboardScroll(forKey:shift:)` / `scrollAmount(for:in:)`）。**キーの割り当ては web 面（`viewer-src/keyboard.ts` の `resolveScrollKey`）と同じ**で、Space・↑↓・j/k・Shift 付きの半ページだけを受ける（← → や Page Up/Down は両面とも足さない）。送り量だけは違い、PDF の Space は**可視高ちょうど**（オーバーラップ無し）——ページ区切りがあるので重ねる必要がなく、縦フィット時にページ単位で読み進められる（TASK-577）。WebView 面の `ContentUpdatePlanner`（純関数）にあたる層で、書き込みは `ZoomingPDFView` が行う |
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
- **その他ファイル種別**: SVG / HTML / CSV・TSV / 画像 / 各種ソースコードは
  `FileType` の判定に従い、ソースコードは highlight.js でシンタックスハイライトする
- **PDF の扱い**: viewer.html を通らない。読み込みは `Data` のまま
  （`ViewerLoadPipeline.Outcome` の `.binary`。base64 化しないのは `PDFView` が
  `Data` を直接受けられるため）運び、`PDFPreviewView` が `PDFView` で描く（ADR 0009）。
  PDF として開けないデータは `RejectReason.damagedDocument` で拒否する
  （読み込みは成功しているため、見なければ黙って空白になる）。
  **PDF でも文書内検索ができる**（TASK-570）。実体は PDFKit の `beginFindString` で、
  可否は `FileType.supportsFind`（画像 false / PDF true）が決める——`!isBinaryContent`
  で判定すると、PDF を開けた瞬間に検索対象のテキストを持たない画像まで一緒に開く。
  ジャンプは見出し構造の抽出が別に要るので `canJump` を `!isBinaryContent` で
  閉じたまま（画像も同様）
- **PDF の見え方**: 全ページを縦に連ねて描き（`.singlePageContinuous`）、
  スクロールはページ境界で止まらず連続する。**`autoScales` は使わない**——連続
  スクロールでの `PDFView` の自動追従は幅基準で、ページの下端が画面外に出る
  （実測: 面 400x500 / Letter でページ高 517.65pt）。倍率は面（`ZoomingPDFView`）が
  「1.0 = フィット」の意味で覚え、ウィンドウのリサイズや回転への追従は
  `ZoomingPDFView.layout` が毎レイアウトで入れ直す。⌘0 で 1.0（フィット）へ戻す。
  当初は 1 ページずつ描いてホイールをページ送りへ振り替えていたが、
  ページが瞬時に切り替わる体感の悪さから連続スクロールへ改めた（TASK-567）。
  ページの影は描かない（連続では全ページ分の影が乗り、描画コストの大半を占める。
  実測: 231 ページで 36.5ms → 4.3ms）。フィットは**ページ全体が収まる倍率**で、文書内でいちばん大きいページに合わせる
  （ページごとに合わせ直すと、スクロール中に倍率が動く）。表示位置は 0 が先頭・
  1 が末尾で、`PDFView` のスクロール座標（下へ行くほど y が小さい）との向きの
  変換は `PDFSurfaceLayout.scrollOffset(forFraction:room:)` が持つ。
  表示位置（文書全体に対する 0…1）と 90 度回転（右上に重ねた `PDFRotationOverlay` の
  2 つのボタン。文書全体に効く）は
  ウィンドウの生存期間だけ記憶する（`WindowPresentationMemory`）。倍率だけは
  内容に依存しないユーザーの意図なので、従来どおり `ZoomStore` で per-file 永続
- **CSV/TSV の数値列**: テーブル表示では列単位に書式を判定する（`viewer-src/csv-columns.ts` の
  `classifyCsvColumn`）。二段構えで、第 1 段「非空セルがすべて数値」を満たす列は右寄せ +
  `tabular-nums`、第 2 段の拒否条件（1,000 以上の値が無い / 先頭ゼロ / 全セル同じ桁数で 4 桁以上 /
  4 桁整数が全部 1900〜2100 / 1 始まりの連番 / ヘッダー名が否定語）をすべてくぐった列だけ
  整数部に桁区切りを入れる。**判定は「外さない」を優先**し、肯定側のヘッダー名マッチ
  （`price` / `金額` 等）は使わない。値そのものは書き換えず、小数部は原文のまま残す。
  判定はヘッダー + 先頭 200 データ行で確定させ、チャンク追記（`render.ts` の `appendChunk`）は
  `document-state.ts` の `_mmdCsvColumns` 経由で同じ判定を再利用する。
  無加工の原文はソース表示（`csv-source`）で見られる
- **CSV/TSV の数値表示の設定**: 桁区切りの有無と負の数の表記（通常 / ▲ / 赤字 / ▲+赤字）を
  設定ウィンドウから選べる（`CsvNumberFormatPreference`。app-global、UserDefaults キーは
  `CsvNumberGrouping` / `CsvNegativeStyle`）。右寄せは設定にせず常時。**どの列が金額かは
  推測せず**、設定そのものが意図を運ぶと考えて、上の第 2 段を通った列すべてに適用する
  （コードとみなされた列には桁区切りも ▲ も赤字も掛からない）。
  変更は `GlobalDisplayBroadcaster.applyCsvNumberFormatToAllWindows` で開いている全窓へ
  即時反映される。コードフォントと違い CSS 変数では表せない（セルの HTML 文字列そのものが
  変わる）ため、viewer 側の `_mmdInitCsvNumberFormat` が現在の文書を描き直す。
  QuickLook 拡張には設定が届かないので、既定（桁区切りオン・通常表記）で描く
- **キャンバス（地）の所有者**: 既定では地の色は `ViewerTheme.canvas`（ウィンドウ背景）が
  唯一の定義で、`WKWebView` は透過・CSS も地を塗らない。これによりネイティブ部分と
  WebView 部分が構成上必ず同色になる。**外部の HTML 文書（`.html` / `.htm` のレンダリング
  表示）だけがこの例外**で、ブラウザと同じく文書が canvas ごと所有する
  （`ViewerWebViewFactory.setDocumentOwnsCanvas`）。透過のままだと、明るい背景を前提に
  文字色だけを指定した HTML がダークキャンバス上に載って読めなくなるため。
  適用先は直接ロード経路（`DirectHTMLModeController` の enter / exit）と、
  viewer.html 内の iframe 経路（QuickLook 等、`OneShotRenderer`）の両方。
  iframe の子文書も子自身の `color-scheme` 宣言に従って WebKit が塗り分けるため、
  CSS 側の手当ては持たない。ソース表示中の HTML は befold がコードとして描くので該当しない
- **ズーム**: 0.5〜2.0（ボタン・キーは 25% 刻み、ホイールは連続）、基準スケール 0.75、
  `Cmd +/-`・`Ctrl + ホイール`・% 表示クリックでリセット。`ZoomStore` によりファイル単位で永続化
- **キーボードスクロール**: `Space` / `Shift+Space` で 1 ページ、`↑↓` / `j` `k` で 1 行、
  `Shift+↑↓` で半ページ（`viewer-src/keyboard.ts`）。`scrollBy` は `behavior: 'smooth'` で、
  1 回のキー操作で位置が飛ばないようにする。CSS の `scroll-behavior` は使わない
  （指定すると `scrollTop` への代入まで animate され、位置復元が着地しなくなる）
- **検索・文書内ジャンプの統合バー**（TASK-485.19）: 検索・見出しジャンプ・変更箇所
  ジャンプは、画面右上の1つのバー（`#mmd-bar`）として見える。上段のモード切替
  スイッチ（`viewer-src/bar-mode.ts`）が検索/見出し/変更箇所を切り替え、下段に
  選ばれたモード固有の入力領域（検索は入力欄+3トグル、見出しはレベルトグル、
  変更箇所は無し）を出す。**実装（`find.ts` / `jump.ts`）は従来どおり別モジュールで、
  排他は引き続き `viewer-src/bar.ts` が持つ**。バー全体の開閉は
  `bar.ts` が一元管理し、モード切替スイッチの選択表示・非対応モードの非表示
  （`ViewerCapabilities.canJump(to:)` 由来）は `bar-mode.ts` が薄い調整役として持つ。
  Swift 側は `DocumentCommandController.openBar(kind:)` が単一入口で、
  `kind` を明示すれば常にそのモードを強制し（Edit メニューの各項目）、
  `kind` が `nil`（⌘F の非明示オープン）のときだけ `ViewerCapabilities.showsDiff`
  を見て検索 / 変更箇所ジャンプへ既定を振り分ける。
- **検索**: 大文字小文字区別・単語一致・正規表現の3トグル、次/前移動。
  ただし PDF 面（`PDFFindOverlay`）は大文字小文字区別のトグルだけを持つ
- **文書内ジャンプ**: 文書順に並んだ目印を前後移動する
  （Edit > 見出しへジャンプ… / 変更箇所へジャンプ…）。目印は 2 種類ある。
  **見出し**は Markdown が対象で、**h1 / h2 / h3 のどれを目印にするかを
  バーのトグルで選べる**（既定は 3 つとも ON。3 つとも OFF も正当な状態）。
  レンダリング表示では `h1` / `h2` / `h3` 要素を、**ソース表示では行頭の
  `#` / `##` / `###`（ATX 見出し）を拾う**（TASK-485.17）。トグルの状態は
  両表示で共有し、**同じ文書なら件数と順序が一致する**ことをテストで固定する
  （フェンス内の `#` を見出しにしないこと、レベル選択が両方に効くことが
  この 1 本で同時に落ちる）。setext 見出し（`===` / `---` の下線）はソース側の
  対象外で、この不変条件は ATX 見出しで書かれた文書について成り立つ。
  どちらを拾うかは **`_mmdDocument.shape()`（render が実際に描いた形）だけ**で決め、
  表示モードや type から推し直さず、DOM の形でも判定しない。特に
  `table.code-table` を探す形は採れない——差分テーブルも同じクラスを名乗るため
  （TASK-318 と同型）。`shape` が `'code'` のときだけソース行走査へ入るので、
  差分表示・CSV ソース表示・Markdown 以外のソース表示は列挙に入らず 0 件になる。
  **種別では capability を閉じない**（`canJump` に fileType を持ち込むと
  ソースの関数定義ジャンプ = TASK-485.4 が来た時点で条件が反転する）。
  目印が 0 個であることは 0/0 表示が伝える、という
  `canJumpToChangeBlock` と同じ立場を取る。
  **変更ブロック**は差分表示が対象で、連続する削除行とその直後の追加行のまとまりを
  1 件として数える。数え方はハンク単位ではない（`GitDiffReader` が 100 万行の文脈を
  指定するためファイル全体が 1 ハンクになりうる）。番号は描画時に
  `viewer-src/diff-html.ts` の `assignChangeBlockIndexes` が `hunk.lines` へ振り、
  `data-diff-block` 属性として出す。インラインと左右分割は同じ行データから番号を
  受け取るため、**レイアウトを切り替えても件数・順序・現在位置が変わらない**
  （列挙側は DOM のクラスではなくこの属性だけを見る）。
  アクティブな変更ブロックは**左端の縦帯**で示す（各行の左端セルへ左辺だけの
  インセット影を引くので、複数行のブロックでも 1 本の帯に見える）。行を囲む枠や
  全セルの枠にしないのは、変更行が `.diff-add` / `.diff-del` の地色で既に見えている
  ところへ線を足すと画面が賑やかになりすぎるため。候補の下線も差分表示では出さない。差分表示中は本文が段階読み込み中でも
  変更ブロックは全数そろっているため「表示範囲内」ラベルは出さない
  （差分の表は `setDiff` で渡った全文から組み、`appendChunk` は追記をスキップする）。
  種類ごとの可否は `ViewerCapabilities.canJump(to:)` が持ち、変更ブロックは差分表示を
  選んでいる間だけ使える。**開いている間に使えなくなったらバーは自動的に閉じる**
  （別のファイルへ切り替えた・差分表示から離れた等。TASK-485.18）。
  Swift は「閉じろ」ではなく**いま使える種類の集合**を送り
  （`DocumentRendering.applyJumpAvailability(_:)` → `_mmdApplyJumpAvailability`）、
  viewer 側は開いている種類がそこに無ければ閉じる。集合は
  `DocumentJumpKind.allCases` を `canJump(to:)` で絞って作るため、
  **開く条件と開き続けられる条件が同じ述語**になり、種類を足したときの
  載せ忘れも起きない（列挙を手書きに変えると `DocumentCommandControllerTests` が落ちる）。
  送信の契機は `ViewerWindowController.refreshUIState()` — 表示モード変更・
  ファイル切替・フォルダー一覧⇄文書の切替がすべて通る唯一の再同期点。
  検索バーは同じ扱いにしない。`canFind` は表示モードに依存しないため失効しない。**コマンド経路（`DocumentRendering.openJump(kind:)` と
  `DocumentCommandController.openJump(kind:)`）は種類を生の String ではなく
  `DocumentJumpKind` で運び、`canJump(to:)` で閉じる**。粗い `canJump` だけで通すと
  種類別の規則をメニュー検証だけが守る形になり、メニュー以外の入口（キーバインド・
  ツールバー）が同じ穴を継承するため（TASK-485.7）。文字列へ落とすのは JS 境界の
  `WebViewDocumentRenderer` 1 箇所だけ。検索バーと同じ形の
  「現在位置 / 総数」表示を持ち、`Enter` / `Shift+Enter` で前後へ動く。
  ジャンプバーは入力欄を持たずキーボードフォーカスが乗らないため、この `Enter` は
  バー要素ではなく `document` で拾う。奪う範囲は**素の `Enter` / `Shift+Enter` に限る**
  （`Cmd` / `Ctrl` / `Alt` 付きのチョードは通し、リンク・ボタン・入力欄など
  `Enter` の既定動作を自分で持つ要素にフォーカスがある間もそちらを優先する。
  判定は `viewer-src/keyboard.ts` の `ownsEnterKey`）。
  **バーを開いている間は目印の候補が下線で示され**、次にどこへ飛ぶか分かる
  （文字幅の下線。h1 / h2 が github-markdown-css の border-bottom を持つため、
  要素幅の下線だと候補か判別できない）。
  トグルの状態は**ライブ値が窓ごと・保存値は次に開く窓の出発点**で、最後に操作した状態が
  再起動後も復元される（`HeadingJumpLevelDefaults`。`SidebarDisplayDefaults` と同じ形で
  ADR 0002「窓の状態」に沿う。窓へ渡すのは読み取り API を持たない記録用プロトコルだけ）。
  目印の列挙は `viewer-src/jump-providers.ts` のプロバイダが担い、位置・表示・
  ハイライト・再構築は `viewer-src/jump.ts` のコントローラが持つ（対象を増やすときは
  プロバイダを足す）。バー内のオプション（見出しレベルのトグルなど）は
  プロバイダが `optionsElementId` で宣言し、コントローラは選ばれている種類のものだけを
  表示する（コントローラは中身を知らない）。
  **選べる見出しレベル（h1 / h2 / h3）の単一の情報源は Swift の
  `HeadingJumpLevels.selectableLevels` と JS の `HEADING_LEVELS` の 2 つだけ**で、
  トグルのボタンは後者から生成する（viewer.html には空の入れ物しか置かない）。
  2 つのずれは `ViewerJumpLevelContractTests` が落とす（TASK-485.11。以前は
  Swift のフィルタ域・JS の定数・HTML のボタンの 3 箇所に独立して書かれており、
  JS 側だけ増やすとユーザーの選択が保存時に黙って捨てられた）。検索バーとは同時に開かない（`viewer-src/bar.ts` が排他を持つ）。
  **開発中機能で、`FeatureGate.isDocumentJumpEnabled` が閉じている stable ビルドでは
  メニュー項目自体を構築しない**（`MainMenuBuilder.build` がゲートを必須引数で受け取り、
  閉じていれば区切り線ごと省く）。コマンドの可否は `ViewerCapabilities.canJump` へ
  畳んであるが、`canJump` はゲート閉で常に false になるため、項目を構築すると
  永久にグレーアウトした項目が stable のユーザーへ露出してしまう（TASK-485.8）。
  安定稼働を確認するまでキー等価は割り当てない
- **表示モード切替**: ツールバーの 3 択セグメント（レンダリング / ソース / 差分）と `⌘1`〜`⌘3`。
  ファイル単位に記憶するが、**永続化はしない**——`WindowPresentationMemory` が持ち、
  窓を閉じれば消える（アプリを再起動すると常にレンダリング表示から始まる。TASK-565）。差分レイアウト（上下/左右）は `⌘\\` とツールバーのトグルで切り替え、
  好みの設定としてアプリ全体で共有する（`DiffDisplayPreference`）。ソース相当の内容を出している間は
  行番号トグルを提供
- **戻る/進むナビゲーション**: タブごとの履歴（`NavigationHistory`）、ツールバーボタン・履歴メニュー・
  トラックパッドスワイプ（`SwipeHistoryNavigation`）に対応
- **エラーパネル**: `mermaid.parseError` で構文エラーの詳細メッセージを赤ボーダー・等幅フォントのパネルに表示
- **削除バナー**: ファイル削除時にグレーバナー＋背景色変更
- **キーボードショートカット一覧**: Help のパネルは実装から生成する（表をビューに持たない）。
  メニュー由来はメニュー定義、ビューア内スクロールは `viewer-src/keyboard.ts`、サイドバーは
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
  「変更ファイルのみ」だけは git 管理下でしか意味を持たないため、
  `FileListModel.canFilterChangedFiles`（実体は `BaseDirectoryDescriptor.allowsGitFeatures(_:)`）
  で出し分ける。メニューは項目ごとの有効判定を `SidebarDisplayMenuState.isEnabled(for:)` が持ち
  （`validateMenuItem` に条件を書かない）、サイドバーヘッダーは押せないボタンを残さず
  項目自体を出さない。差分表示と同じ判定を見るので、両者の条件がずれない（TASK-537）。
  ツリー⇄リストの切り替えは開閉状態とカレントフォルダーを引き継ぐ:
  ツリー→リストで展開集合を温存したまま root を `SidebarExpansion` のスナップショットに
  記録し、選択ファイルの親フォルダーへカレントを移す。リスト→ツリーはカレントが
  root の配下なら root と展開を復元して選択までの経路を追加展開し、配下の外なら
  移動先を新しいルートにする（元へ引き戻さない）。この遷移方針は
  `SidebarLayoutTransition` が持ち、ライブ値の更新自体は上の入口を通る。
  展開状態とスナップショットはウィンドウ単位・メモリのみで永続化しない

---

## リモート読み込みの遮断

ビューアは信頼できない文書を開くため、**文書を開いただけで外部ホストへリクエストが
出ない**ことを保つ。出てしまうと、IP・User-Agent・どの文書をいつ開いたかが相手に渡る。

**meta CSP の `img-src` はこの用途に使えない。** viewer.html は
`img-src 'self' data:` を宣言しているが、`file://` で読み込んだ文書では WebKit が
リモート画像の取得を検査しない（実測: リモートバッジが `naturalWidth = 78` で
デコードでき、`securitypolicyviolation` は 1 件も発火しない）。同じ宣言の
`script-src` / `frame-src` は効いているため、CSP 自体は読まれている。宣言は
多層防御として残すが、遮断を担うのは次の 2 層。

| 層 | 実体 | 守る範囲 |
|---|---|---|
| 一次（JS） | `viewer-src/markdown.ts` の `replaceRemoteImages()` | markdown / inline HTML。DOMParser で作った**切り離された文書**の上で `img[src^=http]` を代替表示へ置き換えるため、そもそもリクエストが出ない |
| 二次（ネイティブ） | `RemoteLoadBlocker`（`BefoldRenderKit/`） | JS を通らない直接 HTML モードと、サニタイザをすり抜けた参照。`WKContentRuleList` で `^https?://` / `^wss?://` を block する |

- 二次の適用点は `ViewerWebViewFactory.loadViewerHTML` の 1 箇所。ここが本体アプリ・
  QuickLook 拡張・直接 HTML モードすべての唯一の入口なので、「ブロッカ未適用のまま
  文書が描かれる」余地が構造的に無い（ルールリストの用意は非同期のため、適用の完了を
  待ってから読み込む）
- 一次の `replaceRemoteImages()` は**当たり付けの正規表現を置かず、常に DOMParser を
  通す**。かつては `/<img[^>]+src\s*=\s*["']?\s*https?:/iu` で DOM の往復を省いていたが、
  この形は「非 ASCII を 1 文字でも含む長い文書」で JSC が破滅的にバックトラックし、
  本文が空白のまま返らなくなる（TASK-548。実測: `<img>` 1 つの中の文字数に対して
  24,000 字 379ms / 48,000 字 1,512ms / 96,000 字 5,991ms / 192,000 字 23,666ms の二乗。
  同じ 192,000 字でも全 ASCII なら 1ms）。省ける DOM の往復は 772KB の文書でも 8ms しか
  ないので、判定式を差し替えるのではなく判定そのものを外してある。
  退行は `scripts/webview-smoke.swift` の `checkLargeNonASCIIDocumentRenders` が
  所要時間で検出する（JS 例外は出ないため、検出できるのは時間だけ）
- ルールリストを用意できなくても viewer.html のロードは必ず行う（fail-open）。
  ここで握りつぶすとビューアが空のままになり、「外部画像が出る」より重い故障になる。
  markdown 経路は一次防御が独立に守る
- `url-filter` の正規表現は選択（`|`）を受け付けない（実測: `^(file|data)://` は
  "Disjunctions are not supported yet" でコンパイルに失敗する）。このため
  「許可を列挙して残りを block」はできず、止めたいスキームを列挙する形になっている。
  `file:` / `data:` / `blob:` はどのルールにも一致しないのでそのまま通る
  （埋め込み画像の data URI がこれに当たる）
- 回帰は `scripts/webview-smoke.swift` の `checkExfilBlocked` が `naturalWidth` で測る
  （「画像バイトが取得されたか」を直接測る唯一の指標）。実在するホストを使う点が要件で、
  到達できない URL では遮断が外れていても `naturalWidth = 0` になり常に緑になる

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
