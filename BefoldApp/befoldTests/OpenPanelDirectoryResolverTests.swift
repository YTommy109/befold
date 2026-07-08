@testable import befold
import Foundation
import Testing

@Suite
struct OpenPanelDirectoryResolverTests {
    @Test("記憶されたディレクトリがあればそれを返す")
    func returnsLastOpenDirectoryWhenPresent() {
        let last = URL(fileURLWithPath: "/Users/tester/Documents")
        let home = URL(fileURLWithPath: "/Users/tester")

        let resolved = OpenPanelDirectoryResolver.resolve(
            lastOpenDirectory: last, homeDirectory: home
        )

        #expect(resolved == last)
    }

    @Test("記憶が無ければホームディレクトリを返す")
    func returnsHomeDirectoryWhenLastOpenDirectoryIsNil() {
        let home = URL(fileURLWithPath: "/Users/tester")

        let resolved = OpenPanelDirectoryResolver.resolve(
            lastOpenDirectory: nil, homeDirectory: home
        )

        #expect(resolved == home)
    }
}
