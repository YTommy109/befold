@testable import befold
import Testing

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

    @Test(arguments: [
        ("1.5.0-dev.1", [1, 5, 0], ["dev", "1"]),
        ("v2.0.0-beta.3", [2, 0, 0], ["beta", "3"]),
        ("1.0.0-alpha", [1, 0, 0], ["alpha"]),
    ])
    func parsePrereleaseVersion(input: String, expectedComponents: [Int], expectedPrerelease: [String]) {
        let version = AppVersion(input)
        #expect(version?.components == expectedComponents)
        #expect(version?.prerelease == expectedPrerelease)
    }

    @Test
    func stableVersionHasNilPrerelease() {
        #expect(AppVersion("1.2.3")?.prerelease == nil)
    }

    @Test(arguments: [
        ("1.5.0-dev.1", "1.5.0"), // プレリリース < 正式版
        ("1.5.0-dev.1", "1.5.0-dev.2"), // dev.1 < dev.2
        ("1.5.0-alpha", "1.5.0-beta"), // alpha < beta（文字列比較）
        ("1.4.9", "1.5.0-dev.1"), // 数値部分が小さい < プレリリース
    ])
    func comparePrereleaseVersions(lower: String, higher: String) throws {
        #expect(try #require(AppVersion(lower)) < #require(AppVersion(higher)))
    }

    @Test
    func prereleaseWithSameIdentifiersAreEqual() throws {
        #expect(try #require(AppVersion("1.5.0-dev.1")) == #require(AppVersion("v1.5.0-dev.1")))
    }
}
