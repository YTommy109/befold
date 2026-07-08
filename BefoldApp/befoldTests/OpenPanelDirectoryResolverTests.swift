@testable import befold
import Foundation
import Testing

@Suite
struct OpenPanelDirectoryResolverTests {
    @Test("表示中ファイルのディレクトリがあればそれを返す")
    func returnsCurrentFileDirectoryWhenPresent() {
        let current = URL(fileURLWithPath: "/Users/tester/Documents")
        let home = URL(fileURLWithPath: "/Users/tester")

        let resolved = OpenPanelDirectoryResolver.resolve(
            currentFileDirectory: current, homeDirectory: home
        )

        #expect(resolved == current)
    }

    @Test("表示中ファイルが無ければホームディレクトリを返す")
    func returnsHomeDirectoryWhenCurrentFileDirectoryIsNil() {
        let home = URL(fileURLWithPath: "/Users/tester")

        let resolved = OpenPanelDirectoryResolver.resolve(
            currentFileDirectory: nil, homeDirectory: home
        )

        #expect(resolved == home)
    }
}
