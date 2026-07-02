import Testing
@testable import mmdview

@Suite
struct AppVersionTests {
    @Test(arguments: [
        ("1.2.3", [1, 2, 3]),
        ("v1.2.3", [1, 2, 3]),
        ("0.1", [0, 1]),
        ("10.20.30", [10, 20, 30]),
        ("1.2.3.4", [1, 2, 3, 4]),
        ("01.2.3", [1, 2, 3]),
    ])
    func parseValidVersion(input: String, expected: [Int]) {
        #expect(AppVersion(input)?.components == expected)
    }

    @Test(arguments: ["", "v", "abc", "1.2.beta", "1..2", "-1.2.3", " 1.2.3 "])
    func parseInvalidVersionReturnsNil(input: String) {
        #expect(AppVersion(input) == nil)
    }

    @Test(arguments: [
        ("1.1.1", "1.2.0"),
        ("1.2", "1.2.1"),
        ("1.9.9", "v2.0.0"),
        ("1.9.0", "1.10.0"),
    ])
    func comparesLowerVersionAsLess(lower: String, higher: String) throws {
        #expect(try #require(AppVersion(lower)) < #require(AppVersion(higher)))
    }

    @Test
    func equalityPadsMissingComponents() throws {
        #expect(try #require(AppVersion("1.2")) == #require(AppVersion("1.2.0")))
    }
}
