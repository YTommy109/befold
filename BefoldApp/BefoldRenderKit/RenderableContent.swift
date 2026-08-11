import BefoldKit
import Foundation

/// render() に渡す直前のコンテンツ加工。
public enum RenderableContent {
    /// markdown はローカル画像参照を data URI に差し替える(相対パスの解決基準として
    /// filePath が必要)。ソース表示中は原文をそのまま見せるため、埋め込みは行わない。
    public nonisolated static func make(
        _ content: String, fileType: FileType, filePath: URL?, isSourceMode: Bool,
        embedImages: Bool = true,
        imageEmbedder: MarkdownImageEmbedder = .shared
    ) -> String {
        guard !isSourceMode, fileType == .markdown, let filePath, embedImages else { return content }
        // ロード時のウォームアップと同じキャッシュを引くため、同一インスタンス(本番は .shared)を経由すること。
        return imageEmbedder.embedLocalImages(in: content, baseURL: filePath)
    }
}
