import BefoldKit
import Foundation

enum SortOrder: Sendable {
    case foldersFirst
    case alphabetical
}

struct FileListEntry: Identifiable, Hashable, Sendable {
    enum Kind: Sendable, Hashable {
        case parentNavigation
        case folder
        case file
    }

    let url: URL
    let kind: Kind

    var id: URL {
        url
    }

    /// 拡張子が `FileType.allExtensions` に無い、未知の拡張子のファイルかどうか。
    /// 未知の拡張子でも `FileType.init(url:)` は plaintext としてフォールバックし表示自体は可能なため、
    /// 「開けない」ことは意味しない(表示不能な状態は `ViewerStore.isRejected` が表す)。
    var hasUnknownExtension: Bool {
        kind == .file && !FileType.isSupported(url)
    }
}
