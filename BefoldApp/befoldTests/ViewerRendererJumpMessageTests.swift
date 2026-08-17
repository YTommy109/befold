@testable import befold
@testable import BefoldKit
@testable import BefoldRenderKit
import Testing
import WebKit

/// 見出しジャンプのレベル通知（jumpLevelsChanged）がブリッジから既定値の記録口へ
/// 届くことを検証する。検索・ズーム等の通知は ViewerRendererMessageHandlingTests。
@Suite
@MainActor
struct ViewerRendererJumpMessageTests {
    private typealias Stubs = ViewerRendererMessageStubs

    private func dispatch(_ renderer: ViewerRenderer, name: String, body: Any) {
        Stubs.dispatch(renderer, name: name, body: body)
    }

    private func makeSUT() -> (renderer: ViewerRenderer, delegate: Stubs.Delegate) {
        let renderer = ViewerRenderer()
        let delegate = Stubs.Delegate()
        renderer.delegate = delegate
        return (renderer, delegate)
    }

    @Test("jumpLevelsChanged が見出しレベルの既定値へ書き戻す")
    func jumpLevelsChangedRecordsDefaults() {
        let (renderer, delegate) = makeSUT()
        defer { withExtendedLifetime(delegate) {} } // renderer.delegate は weak
        let recorder = HeadingJumpLevelRecorderSpy()
        renderer.headingJumpLevelRecording = recorder

        dispatch(
            renderer, name: ViewerBridge.jumpLevelsChangedMessageName,
            body: ["levels": ["h1", "h3"]]
        )

        #expect(recorder.recorded == [HeadingJumpLevels(levels: [1, 3])])
    }

    /// 「3 つとも OFF」は正当な値なので、空配列でも記録する
    /// （空だからと弾くと、ユーザーが全部 OFF にした状態が保存されない）。
    @Test("jumpLevelsChanged は空配列も記録する")
    func jumpLevelsChangedRecordsEmptySelection() {
        let (renderer, delegate) = makeSUT()
        defer { withExtendedLifetime(delegate) {} } // renderer.delegate は weak
        let recorder = HeadingJumpLevelRecorderSpy()
        renderer.headingJumpLevelRecording = recorder

        dispatch(renderer, name: ViewerBridge.jumpLevelsChangedMessageName, body: ["levels": [String]()])

        #expect(recorder.recorded == [.none])
    }

    /// JS が送る表現と Swift が読む表現が同じであることを、両端を突き合わせて確かめる。
    /// キー名だけを見る契約テストではこのずれを検知できず、実機で「3 つとも OFF」として
    /// 保存される形で発覚した（JS が数値 [1] を送り、Swift は "h1" を期待していた）。
    @Test("JS が送るレベル表現を Swift がそのまま解釈できる")
    func payloadTokensRoundTripThroughSwift() throws {
        let bundleSource = try String(
            contentsOf: #require(Bundle.befoldKitResources.url(forResource: "viewer-bundle", withExtension: "js")),
            encoding: .utf8
        )
        // JS 側は 'h' + level で組み立てる（headingLevelTokens）。
        #expect(bundleSource.contains("return \"h\" + level;") || bundleSource.contains("'h' + level"))

        let (renderer, delegate) = makeSUT()
        defer { withExtendedLifetime(delegate) {} } // renderer.delegate は weak
        let recorder = HeadingJumpLevelRecorderSpy()
        renderer.headingJumpLevelRecording = recorder

        // Swift 側の保存表現をそのまま送り返しても同じ値になる（往復で崩れない）。
        let sent = HeadingJumpLevels(levels: [1, 3]).storedValue
        dispatch(renderer, name: ViewerBridge.jumpLevelsChangedMessageName, body: ["levels": sent])

        #expect(recorder.recorded == [HeadingJumpLevels(levels: [1, 3])])
    }

    @Test("jumpLevelsChanged のペイロードが配列でなければ記録しない")
    func jumpLevelsChangedIgnoresBrokenPayload() {
        let (renderer, delegate) = makeSUT()
        defer { withExtendedLifetime(delegate) {} } // renderer.delegate は weak
        let recorder = HeadingJumpLevelRecorderSpy()
        renderer.headingJumpLevelRecording = recorder

        dispatch(renderer, name: ViewerBridge.jumpLevelsChangedMessageName, body: ["levels": "h1"])

        #expect(recorder.recorded.isEmpty)
    }
}

/// 見出しレベルの記録口のスパイ。記録専用（読み取り API を持たない）契約をそのまま持つ。
@MainActor
private final class HeadingJumpLevelRecorderSpy: HeadingJumpLevelRecording {
    private(set) var recorded: [HeadingJumpLevels] = []

    func record(_ levels: HeadingJumpLevels) {
        recorded.append(levels)
    }
}
