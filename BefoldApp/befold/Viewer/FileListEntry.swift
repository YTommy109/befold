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
}
