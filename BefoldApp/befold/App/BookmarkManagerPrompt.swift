import BefoldKit
import Foundation

/// ブックマーク管理パネルの文字入力(`.alert` + `TextField`)が扱う用件。
/// 1 つの alert を使い回すための値で、初期値と文言のキーだけを持つ(適用はビューが行う)。
/// `.alert(_:isPresented:presenting:)` の `presenting` は識別子を要求しないので `Identifiable` にはしない。
enum BookmarkManagerPrompt: Equatable {
    /// ブックマークの別名。
    case alias(BookmarkEntry)
    /// `parent` の下に新しいフォルダーを作る。
    case newFolder(parent: [String])
    /// フォルダーの改名。
    case renameFolder([String])

    /// 入力欄の初期値。改名は今の名前、別名は今の別名(無ければ空)。
    var initialText: String {
        switch self {
        case let .alias(entry): entry.alias ?? ""
        case .newFolder: ""
        case let .renameFolder(path): path.last ?? ""
        }
    }

    var titleKey: String.LocalizationValue {
        switch self {
        case .alias: "bookmarks.manager.renameAlias.title"
        case .newFolder: "bookmarks.manager.newFolder.title"
        case .renameFolder: "bookmarks.manager.renameFolder.title"
        }
    }

    var placeholderKey: String.LocalizationValue {
        switch self {
        case .alias: "bookmarks.manager.renameAlias.placeholder"
        case .newFolder, .renameFolder: "bookmarks.manager.folderName.placeholder"
        }
    }

    var applyKey: String.LocalizationValue {
        switch self {
        case .alias, .renameFolder: "bookmarks.manager.renameAlias.apply"
        case .newFolder: "bookmarks.manager.create"
        }
    }

    /// alert の本文。別名はどのファイルかをパスで示し、フォルダーは置き場所を示す。
    var message: String {
        switch self {
        case let .alias(entry): entry.path
        case let .newFolder(parent): parent.joined(separator: " / ")
        case let .renameFolder(path): path.dropLast().joined(separator: " / ")
        }
    }
}
