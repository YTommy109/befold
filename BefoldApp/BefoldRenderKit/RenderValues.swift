import BefoldKit
import WebKit

/// ソース表示へ重ねる git 差分の状態。本文とレイアウトは必ず一緒に動くため
/// 1 つの値として持つ(片方だけ送られて、旧レイアウトで新しい差分が描かれるのを防ぐ)。
public struct DiffState: Equatable, Sendable {
    public let text: String?
    public let layout: ViewerBridge.DiffLayout
    public init(text: String?, layout: ViewerBridge.DiffLayout) {
        self.text = text
        self.layout = layout
    }

    /// 差分を出さない状態。
    public static let none = DiffState(text: nil, layout: .inline)
}

/// _mmdSetTruncated へ送る切り詰め状態と表示行数のペア。非切り詰め時の
/// 行数は 0 に正規化する(切り詰め有無だけが意味を持つ)。failed はチャンク
/// 読込エラーによる打ち切りを示す(通常の再描画経路からは常に false)。
public struct TruncationState: Equatable, Sendable {
    public let isTruncated: Bool
    public let lineCount: Int
    public let failed: Bool
    public init(isTruncated: Bool, lineCount: Int, failed: Bool) {
        self.isTruncated = isTruncated
        self.lineCount = isTruncated ? lineCount : 0
        self.failed = failed
    }

    /// この状態を JS へ反映するスクリプト。3 つのフィールドを呼び出し側で
    /// 手ばらしすると、フィールドが増えたときに渡し漏れる。
    public var script: String {
        ViewerBridge.truncatedScript(isTruncated, lineCount: lineCount, failed: failed)
    }
}

/// `applyRender` の引数をまとめた入力。
/// generation は呼び出し時点の contentUpdateGeneration のスナップショット。画像埋め込み
/// (MainActor 外)から戻った際にこの値と現在値を比較し、後続の updateContent 呼び出しに
/// 追い越されていないかを確認する。
struct RenderRequest {
    let content: String
    let contentRevision: Int
    let fileType: FileType
    let filePath: URL?
    let isSourceMode: Bool
    let showLineNumbers: Bool
    let truncation: TruncationState
    let generation: Int
}

/// `applyAppend` の引数をまとめた入力。`RenderRequest` 参照。
struct AppendRequest {
    let chunk: String
    let contentRevision: Int
    let fileType: FileType
    let filePath: URL?
    let isSourceMode: Bool
    let truncation: TruncationState
    let generation: Int
}

/// `DiffState` / `TruncationState` は ViewerRenderer のネスト型として公開してきた。
/// 呼び出し側(`befold` の ViewerWebView / ViewerContentView)を巻き込まずに宣言だけを
/// トップレベルへ出すため、旧名を typealias で残す。
public extension ViewerRenderer {
    typealias DiffState = BefoldRenderKit.DiffState
    typealias TruncationState = BefoldRenderKit.TruncationState
}
