import BefoldKit
import Foundation
import UniformTypeIdentifiers

/// `UTType` は Apple 専用なので、プラットフォーム非依存の BefoldKit ではなくアプリ側に置く
/// (scripts/check-befoldkit-platform-free.sh)。
extension BookmarkEntry {
    /// 一覧に出すアイコンの型。拡張子だけから決め、ブックマーク先には触れない(TASK-620.1)。
    /// フォルダーはブックマークできないので種別は持たない。以前の版で追加されたフォルダーも
    /// 消さずに残すが、拡張子の無い名前は汎用の書類アイコンになる(TASK-621)。
    var iconType: UTType {
        let pathExtension = (path as NSString).pathExtension
        guard !pathExtension.isEmpty else { return .data }
        return UTType(filenameExtension: pathExtension) ?? .data
    }
}
