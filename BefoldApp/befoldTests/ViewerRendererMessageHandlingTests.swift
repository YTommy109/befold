import BefoldKit
@testable import BefoldRenderKit
import BefoldTestSupport
import Testing
import WebKit

/// JS → Swift 方向の postMessage デコード・ディスパッチ(ViewerRenderer+MessageHandling)と、
/// allowsInteractiveBridging によるハンドラ登録の多層防御(messageHandlerNames)を検証する。
/// ViewerBridgeTests は Swift → JS 方向のみをカバーしているため、逆方向をここで補う。
@Suite
@MainActor
struct ViewerRendererMessageHandlingTests {
    private typealias Stubs = ViewerRendererMessageStubs

    private func dispatch(_ renderer: ViewerRenderer, name: String, body: Any) {
        Stubs.dispatch(renderer, name: name, body: body)
    }

    /// renderer と delegate を組み立てて配線する。ほぼ全テストの先頭 3 行だった定型セットアップの集約先。
    private func makeSUT() -> (renderer: ViewerRenderer, delegate: Stubs.Delegate) {
        let renderer = ViewerRenderer()
        let delegate = Stubs.Delegate()
        renderer.delegate = delegate
        return (renderer, delegate)
    }

    // MARK: - デコードとディスパッチ(正常系)

    // zoomChanged のデコードは ViewerRendererZoomMessageTests に分けている(file_length)。

    @Test("referenceActivated が href と修飾キーから開き方を決めて onOpenReference へ渡す", arguments: [
        // (metaKey, shiftKey, 期待する開き方)
        (metaKey: false, shiftKey: false, expected: OpenDisposition.currentTab),
        (false, true, .currentTab), // cmd を伴わない shift だけでは currentTab のまま
        (true, false, .newTab),
        (true, true, .newWindow),
    ])
    func referenceActivatedDispatchesReference(metaKey: Bool, shiftKey: Bool, expected: OpenDisposition) {
        let (renderer, delegate) = makeSUT()
        var received: (href: String, disposition: OpenDisposition)?
        delegate.onOpenReference = { received = ($0, $1) }

        dispatch(
            renderer, name: ViewerBridge.referenceActivatedMessageName,
            body: ["href": "./other.md", "metaKey": metaKey, "shiftKey": shiftKey]
        )

        #expect(received?.href == "./other.md")
        #expect(received?.disposition == expected)
    }

    @Test("referenceContextMenu が href を onContextMenu へ渡す")
    func referenceContextMenuDispatchesHref() {
        let (renderer, delegate) = makeSUT()
        var received: String?
        delegate.onContextMenu = { received = $0 }

        dispatch(
            renderer, name: ViewerBridge.referenceContextMenuMessageName,
            body: ["href": "./other.md"]
        )

        #expect(received == "./other.md")
    }

    @Test("referenceContextMenu の href が文字列でなければ onContextMenu を呼ばない")
    func referenceContextMenuIgnoresWrongTypedHref() {
        let (renderer, delegate) = makeSUT()
        var called = false
        delegate.onContextMenu = { _ in called = true }

        dispatch(
            renderer, name: ViewerBridge.referenceContextMenuMessageName,
            body: ["href": 123]
        )

        #expect(!called)
    }

    @Test("scrollPositionChanged が onScrollPositionChanged へ位置/モードを渡す")
    func scrollPositionChangedDispatchesPositionAndMode() {
        let (renderer, delegate) = makeSUT()
        var received: (position: Double, mode: ViewerBridge.ViewMode)?
        delegate.onScrollPositionChanged = { position, _, mode in received = (position, mode) }

        dispatch(
            renderer, name: ViewerBridge.scrollPositionChangedMessageName,
            body: ["position": NSNumber(value: 320.5), "mode": "source"]
        )

        #expect(received?.position == 320.5)
        #expect(received?.mode == .source)
    }

    /// 通知に載る文書は「JS が payload の path で申告した、位置を読んだ時点で DOM に
    /// 出ていた文書」。描画済みミラーは evaluateJavaScript のキュー投入時点で先へ進む
    /// ため、配達時にミラーから推定すると切替の遷移窓で別文書のキーへ保存される
    /// (TASK-393)。ここがミラー参照へ戻ると落ちるよう、ミラーには別の文書を入れておく。
    @Test("scrollPositionChanged は payload の path を通知に載せる(ミラーから推定しない)")
    func scrollPositionChangedCarriesPayloadPath() {
        let (renderer, delegate) = makeSUT()
        renderer.recordRendered(RenderedStateMirror(filePath: URL(fileURLWithPath: "/tmp/queued-next-doc.md")))
        var receivedURL: URL?
        delegate.onScrollPositionChanged = { _, url, _ in receivedURL = url }

        dispatch(
            renderer, name: ViewerBridge.scrollPositionChangedMessageName,
            body: ["position": NSNumber(value: 12.0), "mode": "rendered", "path": "/tmp/dom-doc.md"]
        )

        #expect(receivedURL == URL(fileURLWithPath: "/tmp/dom-doc.md"))
    }

    /// 文書が定まらない間(描画前)の JS は path: null を送る。捨てるかどうかの判断は
    /// 受け取り側(ViewerWindowController)の責務なので、ここでは nil で配達される。
    @Test("scrollPositionChanged の path が無ければ url は nil で配達される")
    func scrollPositionChangedWithoutPathDeliversNilURL() {
        let (renderer, delegate) = makeSUT()
        var received: (url: URL?, called: Bool) = (nil, false)
        delegate.onScrollPositionChanged = { _, url, _ in received = (url, true) }

        dispatch(
            renderer, name: ViewerBridge.scrollPositionChangedMessageName,
            body: ["position": NSNumber(value: 12.0), "mode": "rendered", "path": NSNull()]
        )

        #expect(received.called)
        #expect(received.url == nil)
    }

    @Test("findOptionsChanged が findOptionsPreference へ3トグルを書き戻す")
    func findOptionsChangedWritesBackPreference() {
        let (renderer, delegate) = makeSUT()
        defer { withExtendedLifetime(delegate) {} } // renderer.delegate は weak
        let preference =
            FindOptionsPreference(defaults: makeIsolatedDefaults(prefix: "ViewerRendererMessageHandlingTests"))
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
        let (renderer, delegate) = makeSUT()
        defer { withExtendedLifetime(delegate) {} } // renderer.delegate は weak
        #expect(renderer.isLoadingMoreLines == false)

        dispatch(renderer, name: ViewerBridge.loadMoreLinesMessageName, body: [])

        // handleLoadMoreLines は非同期 Task を張る前に同期でフラグを立てる。
        // 同期テストのため spawn した Task はまだ走らず、ここでは true のままとなる。
        #expect(renderer.isLoadingMoreLines == true)
    }

    @Test("handleLoadMoreLines は onLoadMoreLines の結果を pendingAppend にステージする")
    func handleLoadMoreLinesStagesPendingAppend() async {
        let (renderer, delegate) = makeSUT()
        delegate.onLoadMoreLines = {
            LoadMoreLinesResult(
                chunk: "row2\n", isTruncated: true, lineCount: 2,
                contentRevision: 5, loadFailed: false
            )
        }

        renderer.handleLoadMoreLines()
        // spawn した非同期 Task の完了(isLoadingMoreLines が false に戻る)を待つ。
        await waitUntilYielding { !renderer.isLoadingMoreLines }

        // 描画はここでは行わず(全文 render も appendChunk も評価しない)、次チャンクを
        // ステージするだけ。実描画は updateContent が pendingAppend を消費して行う。
        #expect(renderer.pendingAppend?.chunk == "row2\n")
        #expect(renderer.pendingAppend?.revision == 5)
    }

    @Test("未消費の pendingAppend がある間の続き読み込みはチャンクを累積する")
    func handleLoadMoreLinesAccumulatesUnconsumedChunks() async {
        let (renderer, delegate) = makeSUT()
        var revision = 1
        delegate.onLoadMoreLines = {
            revision += 1
            return LoadMoreLinesResult(
                chunk: revision == 2 ? "A" : "B", isTruncated: true, lineCount: revision,
                contentRevision: revision, loadFailed: false
            )
        }

        // updateContent が消費する前に 2 回続けてステージする(SwiftUI 更新の合体を模す)。
        renderer.handleLoadMoreLines()
        await waitUntilYielding { !renderer.isLoadingMoreLines }
        renderer.handleLoadMoreLines()
        await waitUntilYielding { !renderer.isLoadingMoreLines }

        // 上書きせず累積し、DOM への追記漏れを防ぐ。revision は最新を採る。
        #expect(renderer.pendingAppend?.chunk == "AB")
        #expect(renderer.pendingAppend?.revision == 3)
    }

    @Test("onLoadMoreLines が nil を返すと pendingAppend はステージされない")
    func handleLoadMoreLinesNilResultDoesNotStage() async {
        let (renderer, delegate) = makeSUT()
        delegate.onLoadMoreLines = { nil }

        renderer.handleLoadMoreLines()
        await waitUntilYielding { !renderer.isLoadingMoreLines }

        #expect(renderer.pendingAppend == nil)
    }

    // MARK: - 不正 body(型不一致・キー欠落)は無視される

    @Test("referenceActivated の必須キーが欠けていれば onOpenReference を呼ばない")
    func referenceActivatedIgnoresMissingKeys() {
        let (renderer, delegate) = makeSUT()
        var called = false
        delegate.onOpenReference = { _, _ in called = true }

        // shiftKey が欠落
        dispatch(
            renderer, name: ViewerBridge.referenceActivatedMessageName,
            body: ["href": "./other.md", "metaKey": true]
        )

        #expect(called == false)
    }

    @Test("referenceActivated の href が文字列でなければ onOpenReference を呼ばない")
    func referenceActivatedIgnoresWrongTypedHref() {
        let (renderer, delegate) = makeSUT()
        var called = false
        delegate.onOpenReference = { _, _ in called = true }

        dispatch(
            renderer, name: ViewerBridge.referenceActivatedMessageName,
            body: ["href": 42, "metaKey": true, "shiftKey": false]
        )

        #expect(called == false)
    }

    @Test("scrollPositionChanged の mode が不正な文字列なら onScrollPositionChanged を呼ばない")
    func scrollPositionChangedIgnoresInvalidMode() {
        let (renderer, delegate) = makeSUT()
        var called = false
        delegate.onScrollPositionChanged = { _, _, _ in called = true }

        dispatch(
            renderer, name: ViewerBridge.scrollPositionChangedMessageName,
            body: ["position": NSNumber(value: 10.0), "mode": "diagonal"]
        )

        #expect(called == false)
    }

    @Test("findOptionsChanged の値が Bool でなければ preference を書き換えない")
    func findOptionsChangedIgnoresNonBoolValues() {
        let (renderer, delegate) = makeSUT()
        defer { withExtendedLifetime(delegate) {} } // renderer.delegate は weak
        let preference =
            FindOptionsPreference(defaults: makeIsolatedDefaults(prefix: "ViewerRendererMessageHandlingTests"))
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
        let (renderer, delegate) = makeSUT()
        var called = false
        delegate.onZoomChanged = { _, _ in called = true }

        dispatch(renderer, name: "somethingElse", body: NSNumber(value: 2.0))

        #expect(called == false)
    }

    // MARK: - 登録リストとルーティングの単一情報源

    /// 登録リストが BridgeMessage から導出されていることを固定する。
    /// 手書きの配列に戻ると、enum に足したメッセージが登録されないまま気付けなくなる。
    @Test("登録するハンドラ名は BridgeMessage の rawValue から導出される")
    func handlerNamesAreDerivedFromBridgeMessage() {
        let all = Set(ViewerBridge.BridgeMessage.allCases.map(\.rawValue))
        let interactiveOnly = Set(
            ViewerBridge.BridgeMessage.allCases
                .filter { !$0.requiresInteractiveBridging }
                .map(\.rawValue)
        )

        #expect(Set(ViewerWebViewFactory.messageHandlerNames(for: .allEnabled)) == all)
        #expect(Set(ViewerWebViewFactory.messageHandlerNames(for: .quickLookRestricted)) == interactiveOnly)
    }

    // MARK: - allowsInteractiveBridging によるハンドラ登録の多層防御

    @Test("allEnabled では 5 種すべてのハンドラ名が登録される")
    func handlerNamesIncludeInteractiveWhenEnabled() {
        let names = ViewerWebViewFactory.messageHandlerNames(for: .allEnabled)

        #expect(names.contains(ViewerBridge.findOptionsChangedMessageName))
        #expect(names.contains(ViewerBridge.zoomChangedMessageName))
        #expect(names.contains(ViewerBridge.scrollPositionChangedMessageName))
        #expect(names.contains(ViewerBridge.loadMoreLinesMessageName))
        #expect(names.contains(ViewerBridge.referenceActivatedMessageName))
    }

    @Test("allowsInteractiveBridging=false では referenceActivated/loadMoreLines を登録しない")
    func handlerNamesExcludeInteractiveWhenDisabled() {
        let features = RendererFeatures.quickLookRestricted
        let names = ViewerWebViewFactory.messageHandlerNames(for: features)

        // 非インタラクティブでも必要な 3 種は残る
        #expect(names.contains(ViewerBridge.findOptionsChangedMessageName))
        #expect(names.contains(ViewerBridge.zoomChangedMessageName))
        #expect(names.contains(ViewerBridge.scrollPositionChangedMessageName))
        // 攻撃面となる 2 種は登録されない
        #expect(!names.contains(ViewerBridge.loadMoreLinesMessageName))
        #expect(!names.contains(ViewerBridge.referenceActivatedMessageName))
    }
}
