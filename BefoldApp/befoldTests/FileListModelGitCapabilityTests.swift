@testable import befold
import BefoldKit
import Foundation
import Testing

/// 「変更のあるファイルのみ」を出してよいかが、**基準ディレクトリの事実から導出される**
/// こと(TASK-537)。メニューもサイドバーヘッダーもこの値だけを見るので、ここがずれると
/// 両方が同時にずれる。
@Suite
@MainActor
struct FileListModelGitCapabilityTests {
    private func makeModel() -> FileListModel {
        FileListModel(
            currentDirectory: URL(fileURLWithPath: "/tmp/FileListModelGitCapabilityTests"),
            entries: [],
            selection: nil
        )
    }

    private func descriptor(_ lookup: GitRootLookup) -> BaseDirectoryDescriptor {
        BaseDirectoryDescriptor(
            rootLookup: lookup,
            workspaceRoot: URL(fileURLWithPath: "/tmp/FileListModelGitCapabilityTests")
        )
    }

    @Test("git ルートを開いていれば絞り込める")
    func allowsInsideGitRoot() {
        let model = makeModel()
        model.baseDirectory = descriptor(
            .root(URL(fileURLWithPath: "/tmp/FileListModelGitCapabilityTests"))
        )

        #expect(model.canFilterChangedFiles)
    }

    @Test("git 管理外・扱えないリポジトリでは絞り込めない")
    func rejectsOutsideGit() {
        let plain = makeModel()
        plain.baseDirectory = descriptor(.notARepository)
        #expect(!plain.canFilterChangedFiles)

        let unusable = makeModel()
        unusable.baseDirectory = descriptor(.undetermined)
        #expect(!unusable.canFilterChangedFiles)
    }

    /// 基準ディレクトリの解決は非同期。未解決のうちから落とすと、初回表示で
    /// 「出ていたボタンが消える」ではなく「無かったボタンが現れる」側の
    /// 入れ替わりが起きる。
    @Test("基準ディレクトリが未解決なら落とさない")
    func doesNotDegradeWhileUndetermined() {
        #expect(makeModel().baseDirectory == nil)
        #expect(makeModel().canFilterChangedFiles)
    }
}
