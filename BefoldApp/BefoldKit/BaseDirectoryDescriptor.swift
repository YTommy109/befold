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
    }

    public let kind: Kind
    /// 基準ディレクトリそのもの。ツールチップのフルパス表示に使う。
    public let url: URL

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
}
