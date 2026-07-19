import Foundation

/// ViewerWebView の Swift 側レンダリング機能を有効/無効に切り替えるフラグ。
/// viewer.html へ注入する JS 側 hostFeatures(ViewerBridge.hostFeaturesScript)とは別に、
/// ネイティブコード経路(loadFileURL によるサンドボックス越境 read)を制御する。
/// QuickLook 拡張(.appex)は対象ファイル単体の read しか持たないため、
/// 親ディレクトリ・兄弟ファイルへアクセスするこれらの機能を無効化する必要がある。
public struct RendererFeatures: Equatable, Sendable {
    /// true のとき、.html ファイルを viewer.html を経由せず loadFileURL で直接ロードする
    /// (loadFileURL の allowingReadAccessTo に親ディレクトリを要求する)。
    public let allowDirectHTML: Bool
    /// true のとき、markdown 内のローカル画像参照(相対パス含む)を data URI に埋め込む
    /// (兄弟ファイルの read を要求する)。
    public let embedImages: Bool
    /// true のとき、referenceActivated/loadMoreLines の postMessage ブリッジ(JS → Swift)を
    /// 有効にする。false の場合、ViewerWebView はこの2つの WKScriptMessageHandler を
    /// 登録せず(Swift 側)、viewer.html の hostFeatures(JS 側)にも無効を伝えて postMessage
    /// 呼び出し自体を抑止する多層防御を行う。QuickLook 拡張のような1回描画のみの静的
    /// プレビューでは、リンク遷移(NSWorkspace.open 等)や追加チャンク読込といった
    /// インタラクティブな機能自体が不要かつ攻撃面になるため無効化を想定する。
    public let allowsInteractiveBridging: Bool

    public init(allowDirectHTML: Bool, embedImages: Bool, allowsInteractiveBridging: Bool = true) {
        self.allowDirectHTML = allowDirectHTML
        self.embedImages = embedImages
        self.allowsInteractiveBridging = allowsInteractiveBridging
    }

    /// アプリ本体向けの既定値。全機能とも有効。
    public static let allEnabled = RendererFeatures(allowDirectHTML: true, embedImages: true)
}
