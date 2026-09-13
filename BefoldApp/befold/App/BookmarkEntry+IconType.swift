import BefoldKit
import Foundation
import UniformTypeIdentifiers

/// `UTType` は Apple 専用なので、プラットフォーム非依存の BefoldKit ではなくアプリ側に置く
/// (scripts/check-befoldkit-platform-free.sh)。
extension BookmarkEntry {
    /// 一覧に出すアイコンの型。拡張子と記録済みの種別だけから決め、ブックマーク先には触れない。
    /// 種別の記録が無い既存データは拡張子が無ければフォルダーと推定する。
    var iconType: UTType {
        if isDirectory == true { return .folder }
        let pathExtension = (path as NSString).pathExtension
        // ponytail: 記録の無い拡張子なしのファイル(Makefile 等)はフォルダーに見える。付け直せば直る
        if pathExtension.isEmpty { return isDirectory == nil ? .folder : .data }
        return UTType(filenameExtension: pathExtension) ?? .data
    }
}
