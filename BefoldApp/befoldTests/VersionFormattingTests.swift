import BefoldKit
import Testing

/// `"<short> (<build>)"` 形式の共通フォーマッタ(GUI About / CLI --version / QuickLook バッジ
/// が共有する単一情報源)の組み立てを検証する。
@Suite
struct VersionFormattingTests {
    @Test("build があれば括弧付きで付す")
    func appendsBuildInParentheses() {
        #expect(VersionFormatting.versionString(short: "1.9.1-dev.5", build: "801") == "1.9.1-dev.5 (801)")
    }

    @Test("build が nil なら short のみ(空括弧にしない)")
    func omitsNilBuild() {
        #expect(VersionFormatting.versionString(short: "1.9.1-dev.5", build: nil) == "1.9.1-dev.5")
    }

    @Test("build が空文字なら short のみ(空括弧にしない)")
    func omitsEmptyBuild() {
        #expect(VersionFormatting.versionString(short: "1.9.1-dev.5", build: "") == "1.9.1-dev.5")
    }

    @Test("build が未置換プレースホルダなら short のみ")
    func omitsPlaceholderBuild() {
        let formatted = VersionFormatting.versionString(short: "1.9.1-dev.5", build: "$(CURRENT_PROJECT_VERSION)")
        #expect(formatted == "1.9.1-dev.5")
    }

    @Test("Info.plist から整形済みバージョンを組み立てる")
    func buildsFromInfoDictionary() {
        let formatted = VersionFormatting.versionString(infoDictionary: [
            "CFBundleShortVersionString": "1.9.1-dev.5",
            "CFBundleVersion": "801",
        ])
        #expect(formatted == "1.9.1-dev.5 (801)")
    }

    @Test("短縮バージョンが取れなければ nil(フォールバックは呼び出し側の判断)")
    func returnsNilWithoutShortVersion() {
        #expect(VersionFormatting.versionString(infoDictionary: ["CFBundleVersion": "801"]) == nil)
        #expect(VersionFormatting.versionString(infoDictionary: nil) == nil)
    }

    @Test("空文字・未置換プレースホルダは値なしとして扱う")
    func treatsEmptyAndPlaceholderAsMissing() {
        #expect(VersionFormatting.shortVersion(infoDictionary: ["CFBundleShortVersionString": ""]) == nil)
        #expect(
            VersionFormatting.shortVersion(
                infoDictionary: ["CFBundleShortVersionString": "$(MARKETING_VERSION)"]
            ) == nil
        )
        #expect(VersionFormatting.buildNumber(infoDictionary: ["CFBundleVersion": ""]) == nil)
        #expect(VersionFormatting.buildNumber(infoDictionary: ["CFBundleVersion": "801"]) == "801")
    }
}
