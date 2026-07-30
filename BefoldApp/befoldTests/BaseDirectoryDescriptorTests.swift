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
