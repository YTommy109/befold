import Testing
@testable import mmdview

struct AppVersionTests {
    @Test(arguments: [
        ("1.2.3", [1, 2, 3]),
        ("v1.2.3", [1, 2, 3]),
        ("0.1", [0, 1]),
        ("10.20.30", [10, 20, 30]),
    ])
    func parseValidVersion(input: String, expected: [Int]) {
        #expect(AppVersion(input)?.components == expected)
    }

    @Test(arguments: ["", "v", "abc", "1.2.beta", "1..2", "-1.2.3"])
    func parseInvalidVersionReturnsNil(input: String) {
        #expect(AppVersion(input) == nil)
    }

    @Test
    func compareVersions() throws {
        #expect(try #require(AppVersion("1.1.1")) < #require(AppVersion("1.2.0")))
        #expect(try #require(AppVersion("1.2")) < #require(AppVersion("1.2.1")))
        #expect(try #require(AppVersion("v2.0.0")) > #require(AppVersion("1.9.9")))
        #expect(try #require(AppVersion("1.10.0")) > #require(AppVersion("1.9.0")))
    }

    @Test
    func equalityPadsMissingComponents() throws {
        #expect(try #require(AppVersion("1.2")) == #require(AppVersion("1.2.0")))
    }
}
