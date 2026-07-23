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

    /// `/usr/local/bin/befold` の symlink 経由起動を模した実行ファイルパスから、
    /// 正しく `.app` バンドルのパスを導けることを確認する
    /// (`Bundle.main` は symlink を辿れずこのパスを解決できないため、
    /// AppVersion.current 側で明示的にバンドルを探す必要がある)。
    @Test("実行ファイルパスから親の .app バンドルパスを導出する")
    func bundlePathDerivesAppBundleFromExecutablePath() {
        let executablePath = "/Applications/befold.app/Contents/MacOS/befold"
        #expect(AppVersion.bundlePath(fromExecutablePath: executablePath) == "/Applications/befold.app")
    }

    @Test("actualExecutablePath は nil でない実パスを返す")
    func actualExecutablePathReturnsNonNil() {
        let path = AppVersion.actualExecutablePath()
        #expect(path != nil)
        #expect(path?.isEmpty == false)
    }
}
