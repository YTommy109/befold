@testable import befold
import Testing

/// AppVersion の解決ロジック(Info.plist優先・定数フォールバック)を検証する。
@Suite
struct AppVersionTests {
    @Test("Info.plist に有効な CFBundleShortVersionString があればそれを優先する")
    func prefersInfoDictionaryVersion() {
        let resolved = AppVersion.resolved(infoDictionary: ["CFBundleShortVersionString": "9.9.9-dev.1"])
        #expect(resolved == "9.9.9-dev.1")
    }

    @Test("Info.plist が無い(SPM単体ビルド)場合はフォールバック定数を使う")
    func fallsBackWhenInfoDictionaryIsNil() {
        let resolved = AppVersion.resolved(infoDictionary: nil)
        #expect(resolved == AppVersion.fallback)
    }

    @Test("CFBundleShortVersionString が空文字の場合はフォールバック定数を使う")
    func fallsBackWhenVersionIsEmpty() {
        let resolved = AppVersion.resolved(infoDictionary: ["CFBundleShortVersionString": ""])
        #expect(resolved == AppVersion.fallback)
    }

    @Test("CFBundleShortVersionString が未置換のビルド変数プレースホルダの場合はフォールバック定数を使う")
    func fallsBackWhenVersionIsUnsubstitutedPlaceholder() {
        let resolved = AppVersion.resolved(infoDictionary: ["CFBundleShortVersionString": "$(MARKETING_VERSION)"])
        #expect(resolved == AppVersion.fallback)
    }
}
