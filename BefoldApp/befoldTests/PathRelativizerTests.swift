@testable import befold
import Foundation
import Testing

@Suite
struct PathRelativizerTests {
    @Test("base 直下のファイルはファイル名だけになる")
    func directChildReturnsFileName() {
        let base = URL(fileURLWithPath: "/Users/tester/project")
        let url = URL(fileURLWithPath: "/Users/tester/project/README.md")

        #expect(PathRelativizer.relativePath(of: url, relativeTo: base) == "README.md")
    }

    @Test("ネストしたファイルはサブパスになる")
    func nestedChildReturnsSubPath() {
        let base = URL(fileURLWithPath: "/Users/tester/project")
        let url = URL(fileURLWithPath: "/Users/tester/project/docs/spec.md")

        #expect(PathRelativizer.relativePath(of: url, relativeTo: base) == "docs/spec.md")
    }

    @Test("base の外にあるファイルは絶対パスのままにする")
    func outsideBaseFallsBackToAbsolutePath() {
        let base = URL(fileURLWithPath: "/Users/tester/project")
        let url = URL(fileURLWithPath: "/Users/other/file.md")

        #expect(PathRelativizer.relativePath(of: url, relativeTo: base) == "/Users/other/file.md")
    }

    @Test("base 自身を渡すと空文字列になる")
    func baseItselfReturnsEmptyString() {
        let base = URL(fileURLWithPath: "/Users/tester/project")

        #expect(PathRelativizer.relativePath(of: base, relativeTo: base) == "")
    }
}
