# HTML 外部リソース対応 & ドキュメントタイプ登録 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HTML ファイルの「このアプリで開く」登録と、相対パスの CSS・画像・フォントの読み込みに対応する。

**Architecture:** HTML レンダリング表示時のみ `WKWebView.loadFileURL` で直接読み込み、相対リソースを自然に解決する。ソース表示・削除状態・他ファイルタイプは従来の viewer.html + evaluateJavaScript パスを維持する。

**Tech Stack:** Swift 6 / AppKit + SwiftUI / WKWebView

## Global Constraints

- macOS 14+ / Swift 6 strict concurrency
- Swift Testing フレームワーク（XCTest ではない）
- テスト関数名は英語 camelCase、日本語は `@Test("...")` 表示名
- コミットは Conventional Commits + 日本語

---

### Task 1: HTML ドキュメントタイプ登録

**Files:**
- Modify: `BefoldApp/befold/Info.plist:209-220` (CFBundleDocumentTypes の CSV/TSV エントリの後に追加)
- Modify: `BefoldApp/befoldTests/InfoPlistTests.swift` (テスト追加)

**Interfaces:**
- Consumes: なし
- Produces: Info.plist に `public.html` ドキュメントタイプ宣言（Task 2 以降の前提条件ではないが、完成品として必要）

- [ ] **Step 1: テストを書く**

`BefoldApp/befoldTests/InfoPlistTests.swift` に追加:

```swift
@Test("HTML のドキュメントタイプが宣言されている")
func claimsHtmlContentType() {
    let claimed = claimedContentTypes()
    #expect(claimed.contains("public.html"))
}
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
cd BefoldApp && swift test --filter InfoPlistTests/claimsHtmlContentType
```

Expected: FAIL — `public.html` が claimedContentTypes に含まれていない

- [ ] **Step 3: Info.plist に HTML ドキュメントタイプを追加**

`BefoldApp/befold/Info.plist` の `CFBundleDocumentTypes` 配列内、CSV/TSV エントリ(`</dict>` at line 219)の後に追加:

```xml
<dict>
    <key>CFBundleTypeName</key>
    <string>HTML</string>
    <key>CFBundleTypeRole</key>
    <string>Viewer</string>
    <key>LSHandlerRank</key>
    <string>Alternate</string>
    <key>LSItemContentTypes</key>
    <array>
        <string>public.html</string>
    </array>
</dict>
```

- [ ] **Step 4: テストが通ることを確認**

```bash
cd BefoldApp && swift test --filter InfoPlistTests/claimsHtmlContentType
```

Expected: PASS

- [ ] **Step 5: 全テスト実行**

```bash
cd BefoldApp && swift test
```

Expected: 全テスト PASS

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/befold/Info.plist BefoldApp/befoldTests/InfoPlistTests.swift
git commit -m "feat: HTML ファイルのドキュメントタイプを登録する"
```

---

### Task 2: ViewerWebView に filePath を渡し、HTML 直接ロードを実装する

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift` (filePath パラメータ追加、Coordinator に直接ロードモード追加)
- Modify: `BefoldApp/befold/Viewer/ViewerContentView.swift` (store.filePath を渡す)

**Interfaces:**
- Consumes: `ViewerStore.filePath: URL?`（既存プロパティ）
- Produces: `ViewerWebView` の `filePath: URL?` パラメータ。Coordinator が HTML 直接ロードモードを自動判定。

- [ ] **Step 1: ViewerWebView に filePath パラメータを追加**

`BefoldApp/befold/Viewer/ViewerWebView.swift` の struct プロパティに追加:

```swift
struct ViewerWebView: NSViewRepresentable {
    let content: String
    let fileType: FileType
    let isDeleted: Bool
    let filePath: URL?          // ← 追加
    let initialZoom: Double
    // ... (残りは既存のまま)
}
```

- [ ] **Step 2: Coordinator に直接 HTML ロードの状態管理を追加**

`Coordinator` クラスに以下を追加:

```swift
private var isDirectHTMLMode = false
private var lastDirectHTMLPath: URL?
```

- [ ] **Step 3: Coordinator.updateContent に filePath パラメータと HTML 直接ロード分岐を追加**

`updateContent` メソッドのシグネチャを変更し、HTML 直接ロードの分岐を追加:

```swift
func updateContent(_ content: String, fileType: FileType, isDeleted: Bool, filePath: URL?) {
    let doUpdate = { [weak self] in
        guard let self, let webView else { return }

        if isDeleted {
            // 削除状態は常に viewer.html モードで表示する
            if isDirectHTMLMode {
                isDirectHTMLMode = false
                lastDirectHTMLPath = nil
                reloadViewerHTML(webView: webView) {
                    webView.evaluateJavaScript(ViewerBridge.showDeletedBannerScript)
                }
                return
            }
            if lastWasDeleted != true {
                webView.evaluateJavaScript(ViewerBridge.showDeletedBannerScript)
                lastWasDeleted = true
            }
            return
        }

        // HTML レンダリング表示: loadFileURL で直接ロード
        if fileType == .html, let filePath {
            lastWasDeleted = false
            let pathChanged = filePath != lastDirectHTMLPath
            let contentChanged = content != lastRenderedContent
            guard !isDirectHTMLMode || pathChanged || contentChanged else { return }
            lastRenderedContent = content
            lastRenderedFileType = fileType
            lastDirectHTMLPath = filePath
            isDirectHTMLMode = true
            isReady = false
            webView.loadFileURL(filePath, allowingReadAccessTo: filePath.deletingLastPathComponent())
            return
        }

        // 直接 HTML モードから viewer.html モードへの復帰
        if isDirectHTMLMode {
            isDirectHTMLMode = false
            lastDirectHTMLPath = nil
            lastRenderedContent = nil
            lastRenderedFileType = nil
            reloadViewerHTML(webView: webView) {
                // viewer.html ロード完了後にコンテンツを描画
                guard let script = ViewerBridge.renderScript(content: content, fileType: fileType)
                else { return }
                webView.evaluateJavaScript(script)
            }
            lastWasDeleted = false
            lastRenderedContent = content
            lastRenderedFileType = fileType
            return
        }

        // 従来パス: viewer.html + evaluateJavaScript
        let needsRender = content != lastRenderedContent
            || fileType != lastRenderedFileType
            || lastWasDeleted == true
        guard needsRender else { return }

        lastWasDeleted = false
        lastRenderedContent = content
        lastRenderedFileType = fileType

        guard let script = ViewerBridge.renderScript(content: content, fileType: fileType)
        else { return }
        webView.evaluateJavaScript(script)
    }

    if isReady {
        doUpdate()
    } else {
        pendingUpdate = doUpdate
    }
}
```

- [ ] **Step 4: Coordinator に reloadViewerHTML ヘルパーを追加**

```swift
private func reloadViewerHTML(webView: WKWebView, then completion: @escaping () -> Void) {
    isReady = false
    pendingUpdate = completion
    if let htmlURL = Bundle.l10n.url(forResource: "viewer", withExtension: "html") {
        let resourceDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
    }
}
```

- [ ] **Step 5: updateNSView の呼び出しを更新**

`updateNSView` メソッドの `updateContent` 呼び出しに `filePath` を追加:

```swift
func updateNSView(_ webView: WKWebView, context: Context) {
    context.coordinator.onZoomChanged = onZoomChanged
    context.coordinator.onOpenReference = onOpenReference
    context.coordinator.updateContent(content, fileType: fileType, isDeleted: isDeleted, filePath: filePath)
}
```

- [ ] **Step 6: ViewerContentView を更新して filePath を渡す**

`BefoldApp/befold/Viewer/ViewerContentView.swift`:

```swift
ViewerWebView(
    content: store.content,
    fileType: store.fileType,
    isDeleted: store.isDeleted,
    filePath: store.filePath,        // ← 追加
    initialZoom: initialZoom,
    onZoomChanged: onZoomChanged,
    onOpenReference: onOpenReference,
    webViewProxy: webViewProxy
)
```

- [ ] **Step 7: ビルド確認**

```bash
cd BefoldApp && swift build
```

Expected: ビルド成功（コンパイルエラーなし）

- [ ] **Step 8: 全テスト実行**

```bash
cd BefoldApp && swift test
```

Expected: 全テスト PASS

- [ ] **Step 9: コミット**

```bash
git add BefoldApp/befold/Viewer/ViewerWebView.swift BefoldApp/befold/Viewer/ViewerContentView.swift
git commit -m "feat: HTML ファイルを loadFileURL で直接ロードして外部リソースを読み込む"
```

---

### Task 3: HTML 直接ロード時の Zoom 対応

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift:6-17` (isDirectHTMLMode を公開する仕組み追加)
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift:289-302` (zoom アクションの分岐)

**Interfaces:**
- Consumes: `ViewerWebView.Coordinator.isDirectHTMLMode`（Task 2 で追加）、`WebViewProxy.webView`（既存）、`ZoomStore`（既存）
- Produces: HTML 直接ロード時に `pageZoom` で動作する zoom アクション

- [ ] **Step 1: ViewerWebView に isDirectHTMLMode を外部公開する仕組みを追加**

ViewerWindowController が現在のモードを判定できるようにする。WebViewProxy に状態を追記:

`BefoldApp/befold/Viewer/WebViewProxy.swift`:

```swift
@MainActor
final class WebViewProxy {
    weak var webView: WKWebView?
    var isDirectHTMLMode = false
}
```

Coordinator の `updateContent` 内で、モード切替時に `webViewProxy` の状態も更新する。ViewerWebView に `webViewProxy` への参照は既にあるので、Coordinator にも持たせる:

`ViewerWebView.makeNSView` 内、`context.coordinator.webView = webView` の近くに追加:

```swift
context.coordinator.webViewProxy = webViewProxy
```

Coordinator にプロパティを追加:

```swift
var webViewProxy: WebViewProxy?
```

Coordinator の `updateContent` 内、`isDirectHTMLMode` を変更する各箇所で同期:

```swift
// isDirectHTMLMode = true の箇所:
webViewProxy?.isDirectHTMLMode = true

// isDirectHTMLMode = false の箇所:
webViewProxy?.isDirectHTMLMode = false
```

- [ ] **Step 2: ViewerWindowController の zoom アクションを分岐**

`BefoldApp/befold/App/ViewerWindowController.swift` の zoom メソッドを変更:

```swift
@objc func zoomIn(_ sender: Any?) {
    guard let webView = webViewProxy.webView else { return }
    if webViewProxy.isDirectHTMLMode {
        let newZoom = min(ZoomStore.maxZoom, webView.pageZoom + 0.1)
        webView.pageZoom = newZoom
        zoomStore.setZoom(newZoom, for: fileURL)
    } else {
        webView.evaluateJavaScript(ViewerBridge.zoomInScript)
    }
}

@objc func zoomOut(_ sender: Any?) {
    guard let webView = webViewProxy.webView else { return }
    if webViewProxy.isDirectHTMLMode {
        let newZoom = max(ZoomStore.minZoom, webView.pageZoom - 0.1)
        webView.pageZoom = newZoom
        zoomStore.setZoom(newZoom, for: fileURL)
    } else {
        webView.evaluateJavaScript(ViewerBridge.zoomOutScript)
    }
}

@objc func resetZoom(_ sender: Any?) {
    guard let webView = webViewProxy.webView else { return }
    if webViewProxy.isDirectHTMLMode {
        webView.pageZoom = ZoomStore.defaultZoom
        zoomStore.setZoom(ZoomStore.defaultZoom, for: fileURL)
    } else {
        webView.evaluateJavaScript(ViewerBridge.zoomResetScript)
    }
}
```

- [ ] **Step 3: HTML 直接ロード完了時に保存済み pageZoom を適用**

Coordinator の `webView(_:didFinish:)` で、直接 HTML ロード完了時に保存済み倍率を反映:

```swift
func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    isReady = true
    if isDirectHTMLMode, let zoom = pendingPageZoom {
        webView.pageZoom = zoom
        pendingPageZoom = nil
    }
    pendingUpdate?()
    pendingUpdate = nil
}
```

Coordinator にプロパティを追加:

```swift
var pendingPageZoom: Double?
```

`updateContent` の HTML 直接ロード分岐で、pageZoom を仕込む:

```swift
// isDirectHTMLMode = true の箇所で loadFileURL の前に:
pendingPageZoom = initialPageZoom
```

ViewerWebView の `updateNSView` で `initialZoom` を Coordinator に渡す:

```swift
func updateNSView(_ webView: WKWebView, context: Context) {
    context.coordinator.onZoomChanged = onZoomChanged
    context.coordinator.onOpenReference = onOpenReference
    context.coordinator.initialPageZoom = initialZoom
    context.coordinator.updateContent(content, fileType: fileType, isDeleted: isDeleted, filePath: filePath)
}
```

Coordinator にプロパティを追加:

```swift
var initialPageZoom: Double = 1.0
```

`updateContent` の HTML 直接ロード分岐を更新:

```swift
pendingPageZoom = initialPageZoom
```

- [ ] **Step 4: ビルド確認**

```bash
cd BefoldApp && swift build
```

Expected: ビルド成功

- [ ] **Step 5: 全テスト実行**

```bash
cd BefoldApp && swift test
```

Expected: 全テスト PASS

- [ ] **Step 6: コミット**

```bash
git add BefoldApp/befold/Viewer/ViewerWebView.swift BefoldApp/befold/Viewer/WebViewProxy.swift BefoldApp/befold/App/ViewerWindowController.swift
git commit -m "feat: HTML 直接ロード時の zoom を pageZoom で対応する"
```

---

### Task 4: ソース表示切替の HTML 対応

**Files:**
- Modify: `BefoldApp/befold/Viewer/ViewerStore.swift` (isSourceMode プロパティ追加)
- Modify: `BefoldApp/befold/Viewer/ViewerWebView.swift` (isSourceMode パラメータ追加、updateContent 分岐条件更新)
- Modify: `BefoldApp/befold/Viewer/ViewerContentView.swift` (store.isSourceMode を渡す)
- Modify: `BefoldApp/befold/App/ViewerWindowController.swift:320-348` (toggleSourceView / resetSourceMode の更新)

**Interfaces:**
- Consumes: `WebViewProxy.isDirectHTMLMode`（Task 3）、`ViewerBridge.viewModeScript`（既存）
- Produces: ソース表示とレンダリング表示の切替が HTML ファイルでも動作する

**設計メモ:** `isSourceMode` を `@Observable` な ViewerStore に持たせることで、変更時に SwiftUI の更新サイクルが自動トリガーされる。HTML 直接ロードモードではこの更新サイクル経由で `updateContent` が呼ばれモード切替が行われる。非 HTML ファイルは従来通り `evaluateJavaScript` で即座に切り替え（SwiftUI 経由の updateContent は `needsRender == false` で早期リターン）。

- [ ] **Step 1: ViewerStore に isSourceMode を追加**

`BefoldApp/befold/Viewer/ViewerStore.swift` に追加:

```swift
var isSourceMode: Bool = false
```

- [ ] **Step 2: ViewerWebView にソースモードフラグを追加**

`BefoldApp/befold/Viewer/ViewerWebView.swift` の struct プロパティに追加:

```swift
struct ViewerWebView: NSViewRepresentable {
    let content: String
    let fileType: FileType
    let isDeleted: Bool
    let filePath: URL?
    let isSourceMode: Bool       // ← 追加
    let initialZoom: Double
    // ...
}
```

- [ ] **Step 2b: Coordinator.updateContent にソースモード判定を追加**

HTML 直接ロードの条件を変更:

```swift
// 変更前:
if fileType == .html, let filePath {

// 変更後:
if fileType == .html, !isSourceMode, let filePath {
```

`updateContent` のシグネチャを変更:

```swift
func updateContent(_ content: String, fileType: FileType, isDeleted: Bool, filePath: URL?, isSourceMode: Bool) {
```

`updateNSView` の呼び出しを更新:

```swift
func updateNSView(_ webView: WKWebView, context: Context) {
    context.coordinator.onZoomChanged = onZoomChanged
    context.coordinator.onOpenReference = onOpenReference
    context.coordinator.initialPageZoom = initialZoom
    context.coordinator.updateContent(content, fileType: fileType, isDeleted: isDeleted, filePath: filePath, isSourceMode: isSourceMode)
}
```

- [ ] **Step 3: ViewerContentView を更新して store.isSourceMode を渡す**

`BefoldApp/befold/Viewer/ViewerContentView.swift` — struct プロパティは変更なし。body 内の ViewerWebView 呼び出しに `isSourceMode: store.isSourceMode` を追加:

```swift
ViewerWebView(
    content: store.content,
    fileType: store.fileType,
    isDeleted: store.isDeleted,
    filePath: store.filePath,
    isSourceMode: store.isSourceMode,
    initialZoom: initialZoom,
    onZoomChanged: onZoomChanged,
    onOpenReference: onOpenReference,
    webViewProxy: webViewProxy
)
```

store は `@Observable` なので `isSourceMode` の変更が SwiftUI の再描画をトリガーする。

- [ ] **Step 4: ViewerWindowController の toggleSourceView / resetSourceMode を更新**

ViewerWindowController の `toggleSourceView` を更新:

```swift
@objc func toggleSourceView(_ sender: Any?) {
    isSourceMode.toggle()
    store.isSourceMode = isSourceMode
    if !webViewProxy.isDirectHTMLMode {
        let mode: ViewerBridge.ViewMode = isSourceMode ? .source : .rendered
        webViewProxy.webView?.evaluateJavaScript(ViewerBridge.viewModeScript(mode))
    }
    // HTML 直接ロードモードの場合、isSourceMode の変更が store 経由で
    // SwiftUI の更新サイクルをトリガーし、ViewerWebView.updateNSView →
    // updateContent が呼ばれ、自動的にモード切替が行われる。
    updateSourceToggleAppearance()
}
```

`resetSourceMode` を更新:

```swift
private func resetSourceMode() {
    guard isSourceMode else { return }
    isSourceMode = false
    store.isSourceMode = false
    if !webViewProxy.isDirectHTMLMode {
        webViewProxy.webView?.evaluateJavaScript(ViewerBridge.viewModeScript(.rendered))
    }
    updateSourceToggleAppearance()
}
```

- [ ] **Step 5: ビルド確認**

```bash
cd BefoldApp && swift build
```

Expected: ビルド成功

- [ ] **Step 6: 全テスト実行**

```bash
cd BefoldApp && swift test
```

Expected: 全テスト PASS

- [ ] **Step 7: コミット**

```bash
git add BefoldApp/befold/Viewer/ViewerWebView.swift BefoldApp/befold/Viewer/ViewerContentView.swift BefoldApp/befold/Viewer/ViewerStore.swift BefoldApp/befold/App/ViewerWindowController.swift
git commit -m "feat: HTML 直接ロードとソース表示の切替に対応する"
```

---

### Task 5: 手動検証

**Files:** なし（実行確認のみ）

**Interfaces:**
- Consumes: Task 1-4 の全成果物

- [ ] **Step 1: テスト用 HTML ファイルを用意**

外部 CSS を参照する HTML ファイルを作成して動作確認:

```bash
mkdir -p /tmp/befold-html-test
cat > /tmp/befold-html-test/style.css << 'EOF'
body { font-family: system-ui; background: #f0f0f0; color: #333; padding: 2em; }
h1 { color: #0066cc; border-bottom: 2px solid #0066cc; padding-bottom: 0.5em; }
.card { background: white; border-radius: 8px; padding: 1.5em; box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin-top: 1em; }
EOF

cat > /tmp/befold-html-test/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <link rel="stylesheet" href="style.css">
  <title>Test Page</title>
</head>
<body>
  <h1>befold HTML Test</h1>
  <div class="card">
    <p>外部 CSS が適用されていれば、このカードに白背景・角丸・影が表示される。</p>
  </div>
</body>
</html>
EOF
```

- [ ] **Step 2: アプリをビルドして起動**

```bash
cd BefoldApp && swift build && open .build/debug/befold.app
```

- [ ] **Step 3: 検証項目**

以下を手動で確認する:

1. **Finder テスト**: `/tmp/befold-html-test/index.html` を右クリック → 「このアプリケーションで開く」に befold が表示される
2. **CSS 適用**: befold で `index.html` を開くと、外部 CSS のスタイル（白背景のカード、青い見出し）が表示される
3. **Zoom**: Cmd+`+` / Cmd+`-` / Cmd+`0` でズームイン/アウト/リセットが動作する
4. **ソース切替**: ツールバーのソース表示ボタンで HTML ソースとレンダリング表示が切り替わる
5. **ファイル監視**: `index.html` を編集すると befold の表示がリアルタイムに更新される
6. **他ファイルタイプ**: `.md` / `.mmd` ファイルを開いた場合に従来通り動作する
7. **ファイル切替**: サイドバーで HTML → Markdown → HTML と切り替えて正常動作を確認

- [ ] **Step 4: コミット（必要な修正があれば）**

手動検証で問題が見つかった場合、修正してコミット。
