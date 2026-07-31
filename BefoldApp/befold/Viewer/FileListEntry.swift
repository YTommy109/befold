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
    /// フォルダー配下に対応形式ファイルがあるか(`.folder` のときのみ意味を持つ)。
    /// 一覧構築(DirectoryLister.buildEntries)の時点で事前計算し、「新しいウィンドウで
    /// 開く」の disabled 判定・実行時のディレクトリ列挙を MainActor から追い出す。
    let containsSupportedFile: Bool
    /// url.normalizedPathKey(resolvingSymlinksInPath の syscall)を構築時に事前計算した値。
    /// SidebarNavigator の選択維持判定(entries.contains { $0.pathKey == key })がエントリ数ぶんの
    /// stat を MainActor 上で行わずに済むようにする。
    let pathKey: String

    init(url: URL, kind: Kind, containsSupportedFile: Bool = false) {
        self.url = url
        self.kind = kind
        self.containsSupportedFile = containsSupportedFile
        pathKey = url.normalizedPathKey
    }

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
