import BefoldKit
@testable import BefoldRenderKit
import Testing
import WebKit

/// JS → Swift 方向の postMessage デコード・ディスパッチ(ViewerRenderer+MessageHandling)と、
/// allowsInteractiveBridging によるハンドラ登録の多層防御(messageHandlerNames)を検証する。
/// ViewerBridgeTests は Swift → JS 方向のみをカバーしているため、逆方向をここで補う。
@Suite
@MainActor
struct ViewerRendererMessageHandlingTests {
    /// WKScriptMessage は公開イニシャライザを持たないため、name/body を差し替えた
    /// サブクラスでハンドラへ任意のメッセージを注入する。
    private final class StubScriptMessage: WKScriptMessage {
        private let stubName: String
        private let stubBody: Any

        init(name: String, body: Any) {
            stubName = name
            stubBody = body
            super.init()
        }

        override var name: String {
            stubName
        }

        override var body: Any {
            stubBody
        }
    }

    private func dispatch(_ renderer: ViewerRenderer, name: String, body: Any) {
        renderer.userContentController(
            WKUserContentController(),
            didReceive: StubScriptMessage(name: name, body: body)
        )
    }

    // MARK: - デコードとディスパッチ(正常系)

    @Test("zoomChanged が onZoomChanged へ倍率を渡す")
    func zoomChangedDispatchesZoom() {
        let renderer = ViewerRenderer()
        var received: Double?
        renderer.onZoomChanged = { received = $0 }

        dispatch(renderer, name: ViewerBridge.zoomChangedMessageName, body: NSNumber(value: 1.75))

        #expect(received == 1.75)
    }

    @Test("referenceActivated が onOpenReference へ href/newWindow を渡す")
    func referenceActivatedDispatchesReference() {
        let renderer = ViewerRenderer()
        var received: (href: String, newWindow: Bool)?
        renderer.onOpenReference = { received = ($0, $1) }

        dispatch(
            renderer, name: ViewerBridge.referenceActivatedMessageName,
            body: ["href": "./other.md", "newWindow": true]
        )

        #expect(received?.href == "./other.md")
        #expect(received?.newWindow == true)
    }

    @Test("scrollPositionChanged が onScrollPositionChanged へ位置/モードを渡す")
    func scrollPositionChangedDispatchesPositionAndMode() {
        let renderer = ViewerRenderer()
        var received: (position: Double, mode: ViewerBridge.ViewMode)?
        renderer.onScrollPositionChanged = { received = ($0, $1) }

        dispatch(
            renderer, name: ViewerBridge.scrollPositionChangedMessageName,
            body: ["position": NSNumber(value: 320.5), "mode": "source"]
        )

        #expect(received?.position == 320.5)
        #expect(received?.mode == .source)
    }

    @Test("findOptionsChanged が findOptionsPreference へ3トグルを書き戻す")
    func findOptionsChangedWritesBackPreference() {
        let renderer = ViewerRenderer()
        let preference = FindOptionsPreference(defaults: Self.ephemeralDefaults())
        preference.caseSensitive = false
        preference.wholeWord = false
        preference.useRegex = false
        renderer.findOptionsPreference = preference

        dispatch(
            renderer, name: ViewerBridge.findOptionsChangedMessageName,
            body: ["caseSensitive": true, "wholeWord": false, "useRegex": true]
        )

        #expect(preference.caseSensitive == true)
        #expect(preference.wholeWord == false)
        #expect(preference.useRegex == true)
    }

    @Test("loadMoreLines が handleLoadMoreLines を起動する(isLoadingMoreLines が立つ)")
    func loadMoreLinesInvokesHandler() {
        let renderer = ViewerRenderer()
        #expect(renderer.isLoadingMoreLines == false)

        dispatch(renderer, name: ViewerBridge.loadMoreLinesMessageName, body: [])

        // handleLoadMoreLines は非同期 Task を張る前に同期でフラグを立てる。
        // 同期テストのため spawn した Task はまだ走らず、ここでは true のままとなる。
        #expect(renderer.isLoadingMoreLines == true)
    }

    @Test("handleLoadMoreLines は onLoadMoreLines の結果を pendingAppend にステージする")
    func handleLoadMoreLinesStagesPendingAppend() async {
        let renderer = ViewerRenderer()
        renderer.onLoadMoreLines = {
            LoadMoreLinesResult(
                chunk: "row2\n", isTruncated: true, lineCount: 2,
                contentRevision: 5, loadFailed: false
            )
        }

        renderer.handleLoadMoreLines()
        // spawn した非同期 Task の完了(isLoadingMoreLines が false に戻る)を待つ。
        while renderer.isLoadingMoreLines {
            await Task.yield()
        }

        // 描画はここでは行わず(全文 render も appendChunk も評価しない)、次チャンクを
        // ステージするだけ。実描画は updateContent が pendingAppend を消費して行う。
        #expect(renderer.pendingAppend?.chunk == "row2\n")
        #expect(renderer.pendingAppend?.revision == 5)
    }

    @Test("未消費の pendingAppend がある間の続き読み込みはチャンクを累積する")
    func handleLoadMoreLinesAccumulatesUnconsumedChunks() async {
        let renderer = ViewerRenderer()
        var revision = 1
        renderer.onLoadMoreLines = {
            revision += 1
            return LoadMoreLinesResult(
                chunk: revision == 2 ? "A" : "B", isTruncated: true, lineCount: revision,
                contentRevision: revision, loadFailed: false
            )
        }

        // updateContent が消費する前に 2 回続けてステージする(SwiftUI 更新の合体を模す)。
        renderer.handleLoadMoreLines()
        while renderer.isLoadingMoreLines {
            await Task.yield()
        }
        renderer.handleLoadMoreLines()
        while renderer.isLoadingMoreLines {
            await Task.yield()
        }

        // 上書きせず累積し、DOM への追記漏れを防ぐ。revision は最新を採る。
        #expect(renderer.pendingAppend?.chunk == "AB")
        #expect(renderer.pendingAppend?.revision == 3)
    }

    @Test("onLoadMoreLines が nil を返すと pendingAppend はステージされない")
    func handleLoadMoreLinesNilResultDoesNotStage() async {
        let renderer = ViewerRenderer()
        renderer.onLoadMoreLines = { nil }

        renderer.handleLoadMoreLines()
        while renderer.isLoadingMoreLines {
            await Task.yield()
        }

        #expect(renderer.pendingAppend == nil)
    }

    @Test("RenderedStateMirror.reset は 6 ミラーを一括で破棄する")
    func renderedStateMirrorResetClearsAll() {
        var mirror = ViewerRenderer.RenderedStateMirror()
        mirror.contentRevision = 3
        mirror.fileType = .markdown
        mirror.filePath = URL(fileURLWithPath: "/tmp/a.md")
        mirror.showLineNumbers = true
        mirror.isSourceMode = true
        mirror.truncation = ViewerRenderer.TruncationState(
            isTruncated: true, lineCount: 4, failed: false
        )

        mirror.reset()

        #expect(mirror.contentRevision == nil)
        #expect(mirror.fileType == nil)
        #expect(mirror.filePath == nil)
        #expect(mirror.showLineNumbers == nil)
        #expect(mirror.isSourceMode == nil)
        #expect(mirror.truncation == nil)
    }

    // MARK: - 不正 body(型不一致・キー欠落)は無視される

    @Test("zoomChanged の body が数値でなければ onZoomChanged を呼ばない")
    func zoomChangedIgnoresNonNumberBody() {
        let renderer = ViewerRenderer()
        var called = false
        renderer.onZoomChanged = { _ in called = true }

        dispatch(renderer, name: ViewerBridge.zoomChangedMessageName, body: "1.5")

        #expect(called == false)
    }

    @Test("referenceActivated の必須キーが欠けていれば onOpenReference を呼ばない")
    func referenceActivatedIgnoresMissingKeys() {
        let renderer = ViewerRenderer()
        var called = false
        renderer.onOpenReference = { _, _ in called = true }

        // newWindow が欠落
        dispatch(
            renderer, name: ViewerBridge.referenceActivatedMessageName,
            body: ["href": "./other.md"]
        )

        #expect(called == false)
    }

    @Test("referenceActivated の href が文字列でなければ onOpenReference を呼ばない")
    func referenceActivatedIgnoresWrongTypedHref() {
        let renderer = ViewerRenderer()
        var called = false
        renderer.onOpenReference = { _, _ in called = true }

        dispatch(
            renderer, name: ViewerBridge.referenceActivatedMessageName,
            body: ["href": 42, "newWindow": true]
        )

        #expect(called == false)
    }

    @Test("scrollPositionChanged の mode が不正な文字列なら onScrollPositionChanged を呼ばない")
    func scrollPositionChangedIgnoresInvalidMode() {
        let renderer = ViewerRenderer()
        var called = false
        renderer.onScrollPositionChanged = { _, _ in called = true }

        dispatch(
            renderer, name: ViewerBridge.scrollPositionChangedMessageName,
            body: ["position": NSNumber(value: 10.0), "mode": "diagonal"]
        )

        #expect(called == false)
    }

    @Test("findOptionsChanged の値が Bool でなければ preference を書き換えない")
    func findOptionsChangedIgnoresNonBoolValues() {
        let renderer = ViewerRenderer()
        let preference = FindOptionsPreference(defaults: Self.ephemeralDefaults())
        preference.caseSensitive = false
        preference.wholeWord = true
        preference.useRegex = false
        renderer.findOptionsPreference = preference

        // useRegex が Bool でない
        dispatch(
            renderer, name: ViewerBridge.findOptionsChangedMessageName,
            body: ["caseSensitive": true, "wholeWord": false, "useRegex": "yes"]
        )

        #expect(preference.caseSensitive == false)
        #expect(preference.wholeWord == true)
        #expect(preference.useRegex == false)
    }

    @Test("未知のメッセージ名は無視される")
    func unknownMessageNameIsIgnored() {
        let renderer = ViewerRenderer()
        var called = false
        renderer.onZoomChanged = { _ in called = true }

        dispatch(renderer, name: "somethingElse", body: NSNumber(value: 2.0))

        #expect(called == false)
    }

    // MARK: - allowsInteractiveBridging によるハンドラ登録の多層防御

    @Test("allEnabled では 5 種すべてのハンドラ名が登録される")
    func handlerNamesIncludeInteractiveWhenEnabled() {
        let names = ViewerRenderer.messageHandlerNames(for: .allEnabled)

        #expect(names.contains(ViewerBridge.findOptionsChangedMessageName))
        #expect(names.contains(ViewerBridge.zoomChangedMessageName))
        #expect(names.contains(ViewerBridge.scrollPositionChangedMessageName))
        #expect(names.contains(ViewerBridge.loadMoreLinesMessageName))
        #expect(names.contains(ViewerBridge.referenceActivatedMessageName))
    }

    @Test("allowsInteractiveBridging=false では referenceActivated/loadMoreLines を登録しない")
    func handlerNamesExcludeInteractiveWhenDisabled() {
        let features = RendererFeatures(
            allowDirectHTML: false, embedImages: false, allowsInteractiveBridging: false
        )
        let names = ViewerRenderer.messageHandlerNames(for: features)

        // 非インタラクティブでも必要な 3 種は残る
        #expect(names.contains(ViewerBridge.findOptionsChangedMessageName))
        #expect(names.contains(ViewerBridge.zoomChangedMessageName))
        #expect(names.contains(ViewerBridge.scrollPositionChangedMessageName))
        // 攻撃面となる 2 種は登録されない
        #expect(!names.contains(ViewerBridge.loadMoreLinesMessageName))
        #expect(!names.contains(ViewerBridge.referenceActivatedMessageName))
    }

    /// テストごとに独立したサンドボックスの UserDefaults を返す(標準ドメインを汚さない)。
    private static func ephemeralDefaults() -> UserDefaults {
        let suiteName = "ViewerRendererMessageHandlingTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}
