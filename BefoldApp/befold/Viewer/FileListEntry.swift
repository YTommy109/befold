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

    /// ルート(列挙の起点ディレクトリ)からの相対深さ。ルート直下 = 0、`.parentNavigation` も 0。
    /// 行の左インデント量だけがこの値を読む(SidebarRowIndent.leadingInset(forDepth:))。
    ///
    /// **init の引数にしていない**のが要点。デフォルト引数にすると渡し忘れが
    /// コンパイルエラーにならず静かに 0 になり、96 箇所ある `FileListEntry(...)` の
    /// どこからでも深さを詐称できてしまう(TASK-319 と同型)。値を変えられるのは
    /// `indented(to:)` だけで、本番でそれを呼ぶのは SidebarRowBuilder 1 箇所に閉じる。
    private(set) var depth: Int = 0

    /// ツリー表示のフォルダ行に出す開閉三角の状態。ドリルダウン表示・プレビュー内の
    /// フォルダー一覧・ファイル行では nil で、従来どおりの見た目になる。
    ///
    /// depth と同じく **init の引数にはしない**。書けるのは `disclosing(_:)` だけで、
    /// 本番でそれを呼ぶのは行を組み立てる SidebarRowBuilder と、絞り込み後に
    /// 「見えている子が 0 か」を確定させる SidebarDisclosureResolver の 2 箇所に閉じる。
    private(set) var disclosure: SidebarDisclosureState?

    init(url: URL, kind: Kind, containsSupportedFile: Bool = false) {
        // id が URL のため、SwiftUI の ForEach は行 ID を辞書キーにするたびに URL の
        // Hashable を走らせる。FileManager 由来の NSString 裏打ちのままだと 1 文字ずつの
        // Unicode 正規化になり一覧が固まるので、構築時に native 裏打ちへ揃える。
        self.url = url.nativeBackedFileURL
        self.kind = kind
        self.containsSupportedFile = containsSupportedFile
        // pathKey も git 状態の辞書引き(行ごとに 2 回)とサイドバーの選択維持判定で
        // ハッシュされるため、引数ではなく native 裏打ちに揃えた self.url から作る。
        pathKey = self.url.normalizedPathKey
    }

    var id: URL {
        url
    }

    /// 深さだけを差し替えた同じ行。SidebarRowBuilder が展開した子行を深くするために使う。
    func indented(to depth: Int) -> FileListEntry {
        var copy = self
        copy.depth = depth
        return copy
    }

    /// 開閉三角の状態だけを差し替えた同じ行。
    func disclosing(_ state: SidebarDisclosureState?) -> FileListEntry {
        var copy = self
        copy.disclosure = state
        return copy
    }

    /// 等値・ハッシュから **depth を外す**。同一性は「どのファイルの行か」であって
    /// 「どこにインデントされているか」ではなく、`id`(= url)・FileListEntryIndex の
    /// byID / byPathKey もその意味で作られている。
    ///
    /// 合成のままにすると `FolderListingSource`(FolderListingView の `case shared([FileListEntry]?)`)の
    /// Equatable が要素比較へ降りるため、同じ一覧が深さの違いだけで別物と判定される。
    static func == (lhs: FileListEntry, rhs: FileListEntry) -> Bool {
        lhs.url == rhs.url && lhs.kind == rhs.kind
            && lhs.containsSupportedFile == rhs.containsSupportedFile && lhs.pathKey == rhs.pathKey
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(kind)
        hasher.combine(containsSupportedFile)
        hasher.combine(pathKey)
    }

    /// 拡張子が `FileType.allExtensions` に無い、未知の拡張子のファイルかどうか。
    /// 未知の拡張子でも `FileType.init(url:)` は plaintext としてフォールバックし表示自体は可能なため、
    /// 「開けない」ことは意味しない(表示不能な状態は `ViewerStore.isRejected` が表す)。
    var hasUnknownExtension: Bool {
        kind == .file && !FileType.isSupported(url)
    }
}
