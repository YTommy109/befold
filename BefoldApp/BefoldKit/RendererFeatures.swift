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

    public init(allowDirectHTML: Bool, embedImages: Bool) {
        self.allowDirectHTML = allowDirectHTML
        self.embedImages = embedImages
    }

    /// アプリ本体向けの既定値。両機能とも有効。
    public static let allEnabled = RendererFeatures(allowDirectHTML: true, embedImages: true)
}
