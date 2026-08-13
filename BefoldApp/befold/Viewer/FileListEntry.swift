import BefoldKit
import Foundation

/// サイドバー一覧の並び順。
///
/// **窓が生きている間は窓ごとのライブ値**(ADR 0002 の「文書の状態」の持ち方)。
/// 真実の源は各窓の `FileListModel.sortOrder` で、窓の間で同期はしない。
/// `SidebarDisplayPreference.sortOrder` はそれとは別に「次に窓を開くときの既定値」
/// だけを保存する。読むのは窓の生成時のみ(`SidebarNavigator.init`)で、生きている窓が
/// 読み直すことはない——読み直すと他窓の操作が後から効いてしまう。
/// 利用者の操作による変更は `SidebarNavigator.setSortOrder(_:)` の 1 本を通す
/// (ライブ値の更新と既定値の保存がそこで必ず対になる)。唯一の例外は CLI の `--sort` で、
/// これはその起動限りの窓単位の上書きなので既定値を書き換えない
/// (`ViewerDisplayOptionsApplier` / `SessionRestorer` の doc を参照)。
enum SortOrder: String, Sendable, CaseIterable {
    case foldersFirst
    case alphabetical

    /// 保存値・未知の文字列から読む。キーが無い/壊れているときは従来の既定へ倒す。
    /// `SidebarLayoutMode.stored(_:)` と同じ形。
    static func stored(_ rawValue: String?) -> SortOrder {
        rawValue.flatMap(SortOrder.init(rawValue:)) ?? .foldersFirst
    }
}

struct FileListEntry: Identifiable, Hashable, Sendable {
    enum Kind: Sendable, Hashable {
        case folder
        case file
    }

    let url: URL
    let kind: Kind
    /// フォルダー配下から対応形式ファイルを 1 件取れるか(`.folder` のときのみ意味を持つ)。
    /// 一覧構築(DirectoryLister.buildEntries)の時点で事前計算し、「新しいウィンドウで
    /// 開く」の disabled 判定・実行時のディレクトリ列挙を MainActor から追い出す。
    ///
    /// **読めなかったフォルダも `false`**(列挙失敗と空を区別しない)。理由は
    /// `DirectoryLister.containsSupportedFile(in:)` の doc を参照。
    let containsSupportedFile: Bool
    /// url.normalizedPathKey(resolvingSymlinksInPath の syscall)を構築時に事前計算した値。
    /// SidebarNavigator の選択維持判定(entries.contains { $0.pathKey == key })がエントリ数ぶんの
    /// stat を MainActor 上で行わずに済むようにする。
    let pathKey: String

    /// ルート(列挙の起点ディレクトリ)からの相対深さ。ルート直下 = 0。
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

    // 等値・ハッシュは **合成のまま**にする(全 stored property が参加し、depth と
    // disclosure も含まれる)。この 2 つは `FileListEntryRow` の見た目(インデント量・
    // 開閉三角・ドリルダウンの ">")を決めるため、外すと SwiftUI が「行の内容は
    // 変わっていない」と判定して描き直さない。表示モードをツリー⇄ドリルダウンで
    // 切り替えても、同じディレクトリのままだと一覧が丸ごと等しくなり、モードの
    // 切り替わりが画面に出ない(TASK-361.1 の回帰)。
    //
    // 「同一性は url であって深さではない」を要求するのは
    // `FolderListingSource.shared([FileListEntry]?)` の比較だけなので、そちらは
    // FolderListingView 側で id 比較の `==` を持つ。ここを弱めて解決しない。

    /// 拡張子が `FileType.allExtensions` に無い、未知の拡張子のファイルかどうか。
    /// 未知の拡張子でも `FileType.init(url:)` は plaintext としてフォールバックし表示自体は可能なため、
    /// 「開けない」ことは意味しない(表示不能な状態は `ViewerStore.isRejected` が表す)。
    var hasUnknownExtension: Bool {
        kind == .file && !FileType.isSupported(url)
    }
}
