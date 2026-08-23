import Foundation

/// 相対パスのコピーと Quick Open が「どのフォルダを基準にしているか」を表す値。
///
/// 基準の決定規則は `PathRelativizer.relativePath(of:workspaceRoot:gitRoot:)` と同じ
/// `gitRoot ?? workspaceRoot` で、サイドバーの表示と実際のコピー結果を一致させるために
/// この 1 か所へ規則を寄せる。表示専用の値であり、パス解決そのものには使わない。
public struct BaseDirectoryDescriptor: Equatable, Sendable {
    /// 基準ディレクトリがどちらの規則で決まったか。アイコンとツールチップの出し分けに使う。
    public enum Kind: Equatable, Sendable {
        /// git の作業ツリールート。
        case gitRoot
        /// git 管理外のフォールバック(= workspaceRoot)。
        case plainFolder
        /// git リポジトリではあるが befold(libgit2)では扱えない。基準は workspaceRoot へ
        /// 落ちるが、`plainFolder` と同じ表示にすると「git 管理外」という事実と異なる
        /// 説明になるため区別する(TASK-438.1)。
        case unusableRepository
    }

    public let kind: Kind
    /// 基準ディレクトリそのもの。ツールチップのフルパス表示に使う。
    public let url: URL

    /// git 由来の機能(差分表示・「変更のあるファイルのみ」)を出してよいか。
    ///
    /// **この判定を各 UI が個別に書かない。** 差分表示は `GitDiffAvailability` 経由で、
    /// サイドバーの絞り込みは `FileListModel.canFilterChangedFiles` 経由で、どちらも
    /// ここへ集まる。個別に書くと片方だけが git 管理外で操作できてしまう(TASK-537)。
    ///
    /// **nil(未解決)は「使えない」ではなく「まだ分からない」。** 基準ディレクトリの解決は
    /// 非同期なので、未解決を false にすると初期表示で有効→無効の入れ替わりが起きる。
    /// `GitDiffAvailability` と同じく**確定した否定でだけ落とす**ことで、入れ替わりは
    /// 「有効 → 無効」の 1 方向・1 回に限られる。
    public static func allowsGitFeatures(_ descriptor: BaseDirectoryDescriptor?) -> Bool {
        switch descriptor?.kind {
        case .gitRoot, nil: true
        case .plainFolder, .unusableRepository: false
        }
    }

    /// 表示用のフォルダ名。ボリューム直下(`/`)のように末尾要素を持たないパスでは
    /// 空文字になってラベルが消えるため、そのときはパス表記そのものを名前として使う。
    public var name: String {
        let component = url.standardizedFileURL.lastPathComponent
        return component.isEmpty || component == "/" ? url.standardizedFileURL.path : component
    }

    /// `gitRoot ?? workspaceRoot` 規則で基準ディレクトリを決める。
    public init(gitRoot: URL?, workspaceRoot: URL) {
        if let gitRoot {
            kind = .gitRoot
            url = gitRoot
        } else {
            kind = .plainFolder
            url = workspaceRoot
        }
    }

    /// リポジトリ検出の結果から作る。基準ディレクトリの決め方は
    /// `init(gitRoot:workspaceRoot:)` と同じ `gitRoot ?? workspaceRoot` 規則のままで、
    /// 検出結果が効くのは**種別(表示)だけ**。ここで基準を変えると
    /// `PathRelativizer.relativePath(of:workspaceRoot:gitRoot:)` と食い違う。
    public init(rootLookup: GitRootLookup, workspaceRoot: URL) {
        switch rootLookup {
        case let .root(gitRoot):
            kind = .gitRoot
            url = gitRoot
        case .notARepository:
            kind = .plainFolder
            url = workspaceRoot
        case .undetermined:
            kind = .unusableRepository
            url = workspaceRoot
        }
    }
}
