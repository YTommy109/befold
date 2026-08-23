import BefoldKit
import Foundation
import Testing

@Suite("BaseDirectoryDescriptor")
struct BaseDirectoryDescriptorTests {
    @Test("git ルートがあれば種別 gitRoot で git ルートを基準にする")
    func prefersGitRootWhenAvailable() {
        let descriptor = BaseDirectoryDescriptor(
            gitRoot: URL(fileURLWithPath: "/Users/me/repo"),
            workspaceRoot: URL(fileURLWithPath: "/Users/me/repo/docs")
        )
        #expect(descriptor.kind == .gitRoot)
        #expect(descriptor.url == URL(fileURLWithPath: "/Users/me/repo"))
        #expect(descriptor.name == "repo")
    }

    @Test("git ルートがなければ種別 plainFolder で workspaceRoot を基準にする")
    func fallsBackToWorkspaceRoot() {
        let descriptor = BaseDirectoryDescriptor(
            gitRoot: nil,
            workspaceRoot: URL(fileURLWithPath: "/Users/me/notes")
        )
        #expect(descriptor.kind == .plainFolder)
        #expect(descriptor.url == URL(fileURLWithPath: "/Users/me/notes"))
        #expect(descriptor.name == "notes")
    }

    @Test("扱えないリポジトリは種別 unusableRepository で workspaceRoot を基準にする")
    func distinguishesUnusableRepositoryFromPlainFolder() {
        let workspaceRoot = URL(fileURLWithPath: "/Users/me/repo/docs")
        let unusable = BaseDirectoryDescriptor(rootLookup: .undetermined, workspaceRoot: workspaceRoot)
        let plain = BaseDirectoryDescriptor(rootLookup: .notARepository, workspaceRoot: workspaceRoot)

        #expect(unusable.kind == .unusableRepository)
        // 基準ディレクトリ自体は plainFolder と同じ(gitRoot ?? workspaceRoot 規則を崩さない)。
        // 違うのは種別だけで、その差が表示の出し分けに使われる。
        #expect(unusable.url == plain.url)
        #expect(unusable.kind != plain.kind)
    }

    @Test("検出結果からの初期化は 3 種別を取り違えない")
    func mapsEachLookupToItsOwnKind() {
        let gitRoot = URL(fileURLWithPath: "/Users/me/repo")
        let workspaceRoot = URL(fileURLWithPath: "/Users/me/repo/docs")
        let expected: [(GitRootLookup, BaseDirectoryDescriptor.Kind)] = [
            (.root(gitRoot), .gitRoot),
            (.notARepository, .plainFolder),
            (.undetermined, .unusableRepository),
        ]
        for (lookup, kind) in expected {
            #expect(BaseDirectoryDescriptor(rootLookup: lookup, workspaceRoot: workspaceRoot).kind == kind)
        }
    }

    @Test("末尾スラッシュがあってもフォルダ名は変わらない")
    func ignoresTrailingSlash() {
        let descriptor = BaseDirectoryDescriptor(
            gitRoot: URL(fileURLWithPath: "/Users/me/repo/", isDirectory: true),
            workspaceRoot: URL(fileURLWithPath: "/Users/me")
        )
        #expect(descriptor.name == "repo")
    }

    @Test("ボリューム直下ではラベルが空にならずパス表記を名前に使う")
    func usesPathAsNameAtVolumeRoot() {
        let descriptor = BaseDirectoryDescriptor(
            gitRoot: nil,
            workspaceRoot: URL(fileURLWithPath: "/")
        )
        #expect(descriptor.name == "/")
    }

    @Test("基準の決定規則が PathRelativizer の gitRoot ?? workspaceRoot と一致する")
    func matchesPathRelativizerBaseRule() {
        let file = URL(fileURLWithPath: "/Users/me/repo/docs/a.md")
        let workspaceRoot = URL(fileURLWithPath: "/Users/me/repo/docs")
        for gitRoot in [URL(fileURLWithPath: "/Users/me/repo"), nil] {
            let descriptor = BaseDirectoryDescriptor(gitRoot: gitRoot, workspaceRoot: workspaceRoot)
            #expect(
                PathRelativizer.relativePath(of: file, workspaceRoot: workspaceRoot, gitRoot: gitRoot)
                    == PathRelativizer.relativePath(of: file, relativeTo: descriptor.url)
            )
        }
    }
}

/// git 由来の機能を出してよいかの判定(TASK-537)。差分表示(`GitDiffAvailability`)と
/// サイドバーの「変更のあるファイルのみ」が**同じ判定を見る**ことがこの型の役目なので、
/// 種別ごとの答えをここで固定する。
@Suite
struct BaseDirectoryDescriptorGitFeatureTests {
    private func descriptor(_ kind: BaseDirectoryDescriptor.Kind) -> BaseDirectoryDescriptor {
        let root = URL(fileURLWithPath: "/tmp/example")
        switch kind {
        case .gitRoot: return BaseDirectoryDescriptor(rootLookup: .root(root), workspaceRoot: root)
        case .plainFolder:
            return BaseDirectoryDescriptor(rootLookup: .notARepository, workspaceRoot: root)
        case .unusableRepository:
            return BaseDirectoryDescriptor(rootLookup: .undetermined, workspaceRoot: root)
        }
    }

    @Test("git ルートでだけ git 由来の機能を出す")
    func allowsOnlyInsideGitRoot() {
        #expect(BaseDirectoryDescriptor.allowsGitFeatures(descriptor(.gitRoot)))
        #expect(!BaseDirectoryDescriptor.allowsGitFeatures(descriptor(.plainFolder)))
        #expect(!BaseDirectoryDescriptor.allowsGitFeatures(descriptor(.unusableRepository)))
    }

    /// 未解決を false にすると初期表示で有効→無効の入れ替わりが起きる。確定した否定で
    /// だけ落とす(`GitDiffAvailability` の縮退規則と同じ)。
    @Test("基準ディレクトリが未解決なら落とさない")
    func doesNotDegradeWhileUndetermined() {
        #expect(BaseDirectoryDescriptor.allowsGitFeatures(nil))
    }
}
