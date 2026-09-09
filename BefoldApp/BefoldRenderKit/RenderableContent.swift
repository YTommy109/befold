import BefoldKit
import Foundation

/// render() に渡す直前のコンテンツ加工。
public enum RenderableContent {
    /// render() へ渡す引数一式。
    ///
    /// 種別を `FileType` ではなく JS のトークンで持つ。XSLT 変換表示は拡張子から
    /// 決まらず「xsl を解決できたか」で決まるため、`FileType` に混ぜると
    /// 表示モード・チャンク可否・capabilities の判定に答えを持たない値が入る。
    /// 型が別なので、この値を `RenderedStateMirror` へ記録する誤りは
    /// コンパイルエラーになる(ミラーは丸ごと比較で再描画要否を決めるため、
    /// 描画形を記録するとフル再描画が止まらなくなる)。
    public struct Renderable: Sendable, Equatable {
        public let content: String
        /// `render(content, type, lang)` の第 2 引数。
        public let type: String
        /// 同じく第 3 引数。取らない種別は nil。
        public let lang: String?

        public init(content: String, type: String, lang: String?) {
            self.content = content
            self.type = type
            self.lang = lang
        }

        init(content: String, fileType: FileType) {
            self.init(content: content, type: fileType.jsValue, lang: fileType.renderLangArgument)
        }
    }

    /// markdown はローカル画像参照を data URI に差し替える(相対パスの解決基準として
    /// filePath が必要)。ソース表示中は原文をそのまま見せるため、埋め込みは行わない。
    ///
    /// XML は、同ディレクトリの XSL スタイルシートを解決できたときだけ
    /// `{"xml":…, "xsl":…}` の JSON へ包み、種別を `ViewerXSLTBridge.renderType` に差し替える。
    /// 変換は viewer 側の `XSLTProcessor` が行うため、ここでは xsl を読んで運ぶだけ。
    /// 解決できなければ素通しになり、従来どおりソースコード表示に落ちる。
    ///
    /// - Parameter allowsXSLT: XSLT 変換表示への差し替えを許すか。追記チャンク(文書の
    ///   断片)と切り詰められた内容は構文として閉じておらず、変換にかければ必ず
    ///   パースエラーになるため false を渡す。
    public nonisolated static func make(
        _ content: String, fileType: FileType, filePath: URL?, isSourceMode: Bool,
        allowsXSLT: Bool = false,
        embedImages: Bool = true,
        allowsSiblingFileReads: Bool = true,
        imageEmbedder: MarkdownImageEmbedder = .shared,
        fileReader: any FileReading = DefaultFileReader()
    ) -> Renderable {
        let unchanged = Renderable(content: content, fileType: fileType)
        guard !isSourceMode, let filePath, allowsSiblingFileReads else { return unchanged }
        if fileType == .markdown {
            guard embedImages else { return unchanged }
            // ロード時のウォームアップと同じキャッシュを引くため、同一インスタンス(本番は .shared)を経由すること。
            return Renderable(
                content: imageEmbedder.embedLocalImages(in: content, baseURL: filePath),
                fileType: fileType
            )
        }
        // ponytail: xsl は描画のたびに読み直す(キャッシュ無し)。XML の描画は内容が
        // 変わったときだけで、読みは呼び出し元の withBlockingWork 内なので実測上の
        // 問題は出ていない。頻度が上がるなら MarkdownImageEmbedder と同じ
        // (mtime, size) キャッシュへ寄せる。
        guard allowsXSLT, fileType == .xml,
              let stylesheet = XSLStylesheetResolver.resolve(
                  xml: content, fileURL: filePath, fileReader: fileReader
              ),
              let payload = ViewerXSLTBridge.payload(xml: content, xsl: stylesheet)
        else { return unchanged }
        return Renderable(content: payload, type: ViewerXSLTBridge.renderType, lang: nil)
    }
}
