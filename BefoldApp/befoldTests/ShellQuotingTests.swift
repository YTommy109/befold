@testable import BefoldCLI
import Foundation
import Testing

@Suite
struct ShellQuotingTests {
    @Test(
        "シェルのシングルクォート文字列として安全にエスケープされる",
        arguments: [
            ("normal", "'normal'"),
            ("it's", "'it'\\''s'"),
            ("", "''"),
            ("path with spaces/file.app", "'path with spaces/file.app'"),
            ("$(rm -rf /)", "'$(rm -rf /)'"),
            ("\"quoted\"", "'\"quoted\"'"),
            ("back`tick`", "'back`tick`'"),
            ("'''", "''\\'''\\'''\\'''"),
        ]
    )
    func shellQuotedEscapesValue(input: String, expected: String) {
        #expect(input.shellQuoted == expected)
    }
}
