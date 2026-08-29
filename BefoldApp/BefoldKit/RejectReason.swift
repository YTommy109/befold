import Foundation

/// ファイルを表示できない理由。
public enum RejectReason: Error, Sendable, Equatable {
    /// 読み込みに失敗したなどの非対応形式。
    case unsupportedFormat
    /// ファイルサイズが上限を超えている。
    case fileTooLarge
    /// NUL バイトを含むためバイナリと判定した。
    ///
    /// unsupportedFormat に丸めず独立させているのは、この理由だけが
    /// 「ファイル側が壊れている」ことを示唆するため。汎用文言のままだと
    /// ユーザーは原因を推測できず、テキストのはずのファイルに NUL が
    /// 混入した事故(生成時のエスケープ漏れ等)を見逃す(TASK-260)。
    case binaryContent
    /// PDF として読めなかった(`PDFDocument` の生成に失敗した)。
    ///
    /// 読み込み自体は成功しているため、この理由が無いと `rejectReason` は nil のまま
    /// `UnsupportedFileView` が出ず、`PDFView` が黙って空白を出すだけになる。
    /// unsupportedFormat に丸めないのは binaryContent と同じ理由で、
    /// 「拡張子は .pdf なのに中身が PDF ではない」ことをユーザーに伝えるため。
    case damagedDocument

    /// ユーザー向けの表示文言。BefoldKit のリソースバンドルから取得するため、
    /// アプリ本体だけでなく QuickLook 拡張(appex)からも利用できる。
    public var localizedMessage: String {
        switch self {
        case .unsupportedFormat:
            String(localized: "viewer.unsupported.format", bundle: .befoldKitResources)
        case .fileTooLarge:
            String(localized: "viewer.unsupported.tooLarge", bundle: .befoldKitResources)
        case .binaryContent:
            String(localized: "viewer.unsupported.binary", bundle: .befoldKitResources)
        case .damagedDocument:
            String(localized: "viewer.unsupported.damaged", bundle: .befoldKitResources)
        }
    }

    /// CLI 出力用の英語固定メッセージ。ロケールに依存しない。
    public var cliMessage: String {
        switch self {
        case .unsupportedFormat:
            "This file format is not supported for preview."
        case .fileTooLarge:
            "This file is too large to display."
        case .binaryContent:
            "This file contains NUL bytes and is treated as binary."
        case .damagedDocument:
            "This document is damaged and cannot be displayed."
        }
    }
}
