@testable import befold
import BefoldKit
import Foundation
import Testing

/// 「相対パスをコピー」は、サイドバーの右クリックメニューと本文のパス参照メニューの
/// 2 経路にある。基準ディレクトリがそれぞれで決まる形に戻すと 2 つのメニューが黙って
/// 食い違うため、配線が同じ規則を通っていることをここで押さえる（TASK-422）。
@MainActor
@Suite
struct RelativePathCopyConsistencyTests {
    private func makeFixture() -> ViewerWindowControllerFixture {
        ViewerWindowControllerFixture(
            file: URL(fileURLWithPath: "/tmp/RelativePathCopyConsistencyTests/doc.md"),
            prefix: "RelativePathCopyConsistencyTests"
        )
    }

    @Test("参照メニューの相対パスはサイドバーと同じ規則（baseDirectory 基準）を通る")
    func referenceMenuUsesSameRuleAsSidebar() {
        let fixture = makeFixture()
        defer { fixture.close() }
        let model = fixture.controller.fileListModel
        model.rootDirectory = URL(fileURLWithPath: "/tmp/RelativePathCopyConsistencyTests")
        model.baseDirectory = BaseDirectoryDescriptor(
            gitRoot: URL(fileURLWithPath: "/tmp/repo"),
            workspaceRoot: model.rootDirectory
        )
        let target = URL(fileURLWithPath: "/tmp/repo/src/a.swift")

        let fromReferenceMenu = fixture.controller.referenceMenu.relativePathForCopy(target)

        #expect(fromReferenceMenu == "src/a.swift")
        #expect(fromReferenceMenu == model.relativePathForCopy(target))
    }

    @Test("baseDirectory 未解決でも参照メニューとサイドバーの結果が一致する")
    func referenceMenuMatchesSidebarWhenBaseDirectoryUnresolved() {
        let fixture = makeFixture()
        defer { fixture.close() }
        let model = fixture.controller.fileListModel
        model.rootDirectory = URL(fileURLWithPath: "/tmp/RelativePathCopyConsistencyTests")
        model.baseDirectory = nil
        let target = URL(fileURLWithPath: "/tmp/RelativePathCopyConsistencyTests/sub/a.swift")

        let fromReferenceMenu = fixture.controller.referenceMenu.relativePathForCopy(target)

        #expect(fromReferenceMenu == "sub/a.swift")
        #expect(fromReferenceMenu == model.relativePathForCopy(target))
    }
}
