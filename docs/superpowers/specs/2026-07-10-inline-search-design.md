# プレビュー内検索(Cmd+F)設計

## 概要

現在表示中のプレビュー内容に対する検索機能を追加する。置換機能は持たない。VSCode 風に、大文字小文字区別・単語マッチ・正規表現の3トグルを備えたフローティング検索バーを Cmd+F でプレビュー右上に表示する。

検索対象は常に「その時点で `#diagram-wrap` に描画されている DOM のテキスト」。レンダリング表示中はレンダリング結果、ソース表示中はソースコードを検索する(表示モードの切り替えとは独立に動く、切替時は新しい DOM に対して同じクエリ・トグルで自動的に再検索する)。

3トグルの ON/OFF は `UserDefaults` によりアプリ全体・再起動後も永続化する。検索語(クエリ文字列)自体は永続化しない(次回 Cmd+F 時に直前のクエリを選択済み状態で復元するのみ、セッション内)。

## アーキテクチャ

```
MainMenuBuilder
  └── Edit メニューに「検索…」(Cmd+F) を追加
        └── target: nil (レスポンダチェーン)

ViewerWindowController
  ├── find(_:)                     # 新規アクション。webView.evaluateJavaScript(ViewerBridge.openFindScript())
  └── validateMenuItem             # isDirectHTMLMode 中は無効化(既存 canToggleSourceMode と同列)

ViewerWebView
  └── makeNSView
        └── WKUserScript(atDocumentStart) で window._mmdInitialFindOptions を注入
              (FindOptionsPreference から読む。initialZoomScript / systemFontSizeScript と同列)

ViewerWebView.Coordinator (WKScriptMessageHandler)
  └── findOptionsChanged メッセージ受信 → FindOptionsPreference.save(...)
        (zoomChanged と同列の新規ハンドラ)

FindOptionsPreference (新規、App/FindOptionsPreference.swift)
  └── caseSensitive / wholeWord / useRegex の3 Bool を UserDefaults に永続化
        (HiddenFilesPreference と同じ「薄い永続化専用クラス」パターン、AppDelegate で1つ生成し注入)

ViewerBridge (新規関数を追加)
  ├── openFindScript                    -> "_mmdOpenFind()"
  ├── initialFindOptionsScript(options)  -> "window._mmdInitialFindOptions = {...};"
  └── findOptionsChangedMessageName      -> "findOptionsChanged"

viewer.html / viewer.js (新規ロジック)
  ├── 検索バー DOM・CSS(初期 hidden)
  ├── _mmdOpenFind() / _mmdCloseFind()
  ├── _mmdFindRefresh()          # render() 末尾から呼ばれる。開いていれば同条件で再検索
  ├── _mmdFindRun(query, options)  # マッチ収集・ハイライト構築(viewer.js: 純粋なマッチ範囲計算)
  └── _mmdFindNext() / _mmdFindPrev()  # Enter / Shift+Enter / ボタン
```

## 詳細設計

### 1. 検索バー UI(`viewer.html`)

`<body>` 直下、`.viewer` と兄弟に `#mmd-find-bar`(初期 `display: none`)を追加する。

```html
<div id="mmd-find-bar" class="mmd-find-bar">
  <input id="mmd-find-input" type="text" class="mmd-find-input" placeholder="検索">
  <span id="mmd-find-count" class="mmd-find-count"></span>
  <button id="mmd-find-prev" class="mmd-find-nav" title="前へ (Shift+Enter)">˄</button>
  <button id="mmd-find-next" class="mmd-find-nav" title="次へ (Enter)">˅</button>
  <button id="mmd-find-case" class="mmd-find-toggle" title="大文字・小文字を区別">Aa</button>
  <button id="mmd-find-word" class="mmd-find-toggle" title="単語単位で検索">ab|</button>
  <button id="mmd-find-regex" class="mmd-find-toggle" title="正規表現">.*</button>
  <button id="mmd-find-close" class="mmd-find-close" title="閉じる (Esc)">×</button>
</div>
```

(注: この `placeholder="検索"` は例示。実装では quality-loop レビューで追加された `ViewerBridge.findStringsScript()` により、プレースホルダーを含む検索バーの全文言(ツールチップ・「見つかりません」等)が `window._mmdFindStrings` 経由でローカライズ注入される。対応するキーは `Localizable.xcstrings` の `viewer.find.*` を参照。)

- 位置: `position: fixed; top: 12px; right: 12px;` の半透明パネル(既存 `.diagram-zoom-controls` と近い見た目のトーン)
- トグルボタンは ON 時に `.active` クラスで背景色を付ける
- 正規表現構文エラー時は `#mmd-find-input` に `.mmd-find-error` クラスを付け赤枠にし、`#mmd-find-count` は空にする
- 0件時は `#mmd-find-count` に「見つかりません」を表示
- light/dark 両対応のスタイルを `style.css` に追加(既存の `.diagram-zoom-controls` / `mermaidTheme` と同じ `prefers-color-scheme` の分岐方式に合わせる)

### 2. マッチ範囲計算(`viewer.js`、純粋関数としてユニットテスト可能にする)

```js
// クエリと3トグルから RegExp を組み立てる。不正な正規表現は null を返す。
function buildFindRegExp(query, options) {
  if (!query) return null;
  var source = options.useRegex ? query : query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  if (options.wholeWord) { source = '\\b(?:' + source + ')\\b'; }
  var flags = 'g' + (options.caseSensitive ? '' : 'i');
  try {
    return new RegExp(source, flags);
  } catch (e) {
    return null; // 呼び出し側は構文エラー表示に切り替える
  }
}
```

`viewer.html` 側は `buildFindRegExp` の結果を使って `#diagram-wrap` のテキストノードを歩き(既存 `_walkTextNodes` と同型の再帰関数を検索用に用意し、`_annotatePathRefs` とは独立に持つ)、マッチ箇所を `<mark class="mmd-find-match">` に置換して `_mmdFindMatches`(出現順の配列)を構築する。実行前に必ず前回のマークを平文へ復元してから再走査する(`el.replaceWith(document.createTextNode(el.textContent))` → `parentNode.normalize()`)。

既知の制約(コード内コメントで明記): シンタックスハイライトの `<span>` 境界やパス参照 `<span>` の境界をまたぐ一致は検出しない(`_PATH_RE` と同じ制約の考え方)。

### 3. ナビゲーション・ライブリロード連携

- `_mmdFindNext()` / `_mmdFindPrev()`: `_mmdFindMatches` 内で現在インデックスを循環させ、`mmd-find-match-current` クラスを付け替え、`scrollIntoView({ block: 'center', behavior: 'smooth' })`
- `render()` の末尾(`_annotatePathRefs()` の直後、`_mmdApplyZoom()` の前)に以下を追加する:
  ```js
  if (_mmdFindIsOpen()) { _mmdFindRefresh(); }
  ```
  `_mmdFindRefresh()` は現在の入力値・トグルのまま再検索し、件数・ハイライト・現在位置(可能ならクランプ)を更新する。これによりライブリロード中も検索状態を保ったまま追従する。
- `Esc` で `_mmdCloseFind()`(ハイライト解除、バー非表示)。次回 `_mmdOpenFind()` 時は入力欄に直前のクエリを選択済みで復元する(JS 変数のみ、永続化はしない)。

### 4. `ViewerBridge` 新規関数

```swift
static let findOptionsChangedMessageName = "findOptionsChanged"
static let openFindScript = "_mmdOpenFind()"

struct FindOptions: Codable {
    var caseSensitive: Bool
    var wholeWord: Bool
    var useRegex: Bool
}
```

(注: 実装では `Codable` ではなく `Equatable` に準拠する。この struct は Swift 側で生成し手動で JS 文字列に埋め込むだけでエンコード/デコードされないため。)

```swift
static func initialFindOptionsScript(_ options: FindOptions) -> String {
    "window._mmdInitialFindOptions = { caseSensitive: \(options.caseSensitive), " +
    "wholeWord: \(options.wholeWord), useRegex: \(options.useRegex) };"
}
```

`ViewerBridgeTests` に `bridgeFunctionsExistInViewerHTML` の拡張(`_mmdOpenFind` / `window._mmdInitialFindOptions` / `messageHandlers.findOptionsChanged` の存在確認)を追加する。

### 5. `FindOptionsPreference`(新規、`App/FindOptionsPreference.swift`)

`HiddenFilesPreference` と同じ「薄い永続化専用クラス」パターン。ファイル単位ではなくアプリ全体で1つの状態(`ZoomStore` の per-file 方式とは異なる)。

```swift
@MainActor
final class FindOptionsPreference {
    private let defaults: UserDefaults
    private static let caseSensitiveKey = "FindCaseSensitive"
    private static let wholeWordKey = "FindWholeWord"
    private static let useRegexKey = "FindUseRegex"

    var caseSensitive: Bool { didSet { defaults.set(caseSensitive, forKey: Self.caseSensitiveKey) } }
    var wholeWord: Bool { didSet { defaults.set(wholeWord, forKey: Self.wholeWordKey) } }
    var useRegex: Bool { didSet { defaults.set(useRegex, forKey: Self.useRegexKey) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        caseSensitive = defaults.bool(forKey: Self.caseSensitiveKey)
        wholeWord = defaults.bool(forKey: Self.wholeWordKey)
        useRegex = defaults.bool(forKey: Self.useRegexKey)
    }
}
```

`AppDelegate.init()` で1つ生成し、`ViewerWindowManager` 経由で各 `ViewerWindowController` / `ViewerWebView` に注入する(`zoomStore` と同列)。

### 6. `ViewerWindowController.find(_:)` / メニュー無効化

```swift
@objc func find(_ sender: Any?) {
    guard let webView = webViewProxy.webView, !webViewProxy.isDirectHTMLMode else { return }
    webView.evaluateJavaScript(ViewerBridge.openFindScript)
}
```

`validateMenuItem` に分岐を追加:

```swift
if menuItem.action == #selector(find(_:)) {
    return !webViewProxy.isDirectHTMLMode
}
```

HTML ファイルの直接ロード中(`isDirectHTMLMode == true`)は viewer.html の JS 自体が存在しないため無効化する。画像・PDF・空ファイルなどテキストノードが存在しないケースは特別扱いせず、自然に「見つかりません」を表示する。

### 7. `MainMenuBuilder.makeEditMenuItem()`

`selectAll` の後に区切り線を挟んで追加する。

```swift
menu.addItem(.separator())
menu.addItem(
    withTitle: String(localized: "menu.edit.find", bundle: .l10n),
    action: #selector(ViewerWindowController.find(_:)),
    keyEquivalent: "f"
)
```

`target` は `nil`(レスポンダチェーン経由、`toggleSourceView` と同じ方式)。ローカライズキー: `menu.edit.find`("検索…")。

### 8. 初期トグル状態の注入(`ViewerWebView.makeNSView`)

`ViewerWebView`(struct)に `let findOptionsPreference: FindOptionsPreference` を追加する(`onZoomChanged` 等と同列のプロパティ。`ViewerWindowController` から生成時に渡す)。`fontSizeScript` と同じ位置に以下を追加する。

```swift
let findOptionsScript = WKUserScript(
    source: ViewerBridge.initialFindOptionsScript(
        ViewerBridge.FindOptions(
            caseSensitive: findOptionsPreference.caseSensitive,
            wholeWord: findOptionsPreference.wholeWord,
            useRegex: findOptionsPreference.useRegex
        )
    ),
    injectionTime: .atDocumentStart,
    forMainFrameOnly: true
)
config.userContentController.addUserScript(findOptionsScript)
config.userContentController.add(
    WeakScriptMessageHandler(delegate: context.coordinator),
    name: ViewerBridge.findOptionsChangedMessageName
)
```

`Coordinator.userContentController(_:didReceive:)` に `findOptionsChanged` の分岐を追加し、受け取った `{caseSensitive, wholeWord, useRegex}` を `findOptionsPreference` に書き戻す(`zoomChanged` と同列)。`dismantleNSView` にも `removeScriptMessageHandler(forName: findOptionsChangedMessageName)` を追加する。

## 状態伝搬の流れ

1. ユーザーが Cmd+F(またはメニュー)を押す → `ViewerWindowController.find(_:)` → `_mmdOpenFind()` がバーを表示しフォーカス、直前のクエリを選択済みで復元
2. 入力・トグル操作のたびに `_mmdFindRun()` が再検索してハイライト・件数を更新、トグル変更時は `findOptionsChanged` を postMessage
3. Swift 側 `Coordinator` が受け取り `FindOptionsPreference` に保存(即 `UserDefaults` へ)
4. ファイル変更で `render()` が呼ばれるたびに、バーが開いていれば `_mmdFindRefresh()` が同条件で自動再検索
5. Esc またはバーの × でハイライトを解除しバーを閉じる。次回 Cmd+F では前回クエリ・トグルの状態(トグルは永続化済み、クエリはセッション内)から再開する
6. 新規ウィンドウ生成時は `window._mmdInitialFindOptions` を通じて `UserDefaults` の最新トグル状態を反映する

## テスト計画

- `ViewerBridgeTests`: `initialFindOptionsScript` の埋め込み値、`bridgeFunctionsExistInViewerHTML` への `_mmdOpenFind` / `window._mmdInitialFindOptions` / `messageHandlers.findOptionsChanged` の存在確認追加
- `viewer.js` の `buildFindRegExp`: 通常一致・大文字小文字トグル・単語マッチ・正規表現トグル・不正な正規表現(null 復帰)をユニットテスト(既存 `zoomLabel` 等と同じテストファイルに追加)
- `FindOptionsPreference` のユニットテスト: トグルと `UserDefaults` 永続化・再読み込み(`HiddenFilesPreference` テストと同型)
- 手動テスト: Cmd+F でのバー表示・Esc/×での終了、大文字小文字・単語マッチ・正規表現それぞれの ON/OFF、Enter/Shift+Enter・前後ボタンでの循環ナビゲーション、ソース⇄レンダリング切替時の追従、外部変更によるライブリロード中の検索継続、`.html` ファイル直接表示中の Cmd+F 無効化、画像/PDF 表示時の「見つかりません」表示、複数ウィンドウでのトグル即時永続化(新規ウィンドウにも反映されるか)
