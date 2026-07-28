@testable import BefoldCLI
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

    // MARK: - ビルド番号付き表記(GUI 表記との統一 / TASK-174)

    @Test("short と build が揃えば \"<short> (<build>)\" 形式で返す(GUI About と同体裁)")
    func resolvedWithBuildFormatsShortAndBuild() {
        let resolved = AppVersion.resolvedWithBuild(infoDictionary: [
            "CFBundleShortVersionString": "9.9.9-dev.1",
            "CFBundleVersion": "801",
        ])
        #expect(resolved == "9.9.9-dev.1 (801)")
    }

    @Test("CFBundleVersion が無ければ短縮バージョンのみを返す(空括弧にしない)")
    func resolvedWithBuildOmitsMissingBuild() {
        let resolved = AppVersion.resolvedWithBuild(infoDictionary: ["CFBundleShortVersionString": "9.9.9-dev.1"])
        #expect(resolved == "9.9.9-dev.1")
    }

    @Test("CFBundleVersion が空文字なら短縮バージョンのみを返す(空括弧にしない)")
    func resolvedWithBuildOmitsEmptyBuild() {
        let resolved = AppVersion.resolvedWithBuild(infoDictionary: [
            "CFBundleShortVersionString": "9.9.9-dev.1",
            "CFBundleVersion": "",
        ])
        #expect(resolved == "9.9.9-dev.1")
    }

    @Test("CFBundleVersion が未置換プレースホルダなら短縮バージョンのみを返す")
    func resolvedWithBuildOmitsPlaceholderBuild() {
        let resolved = AppVersion.resolvedWithBuild(infoDictionary: [
            "CFBundleShortVersionString": "9.9.9-dev.1",
            "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        ])
        #expect(resolved == "9.9.9-dev.1")
    }

    @Test("infoDictionary が nil ならフォールバック定数のみ(ビルド番号なし)を返す")
    func resolvedWithBuildFallsBackWithoutBuildWhenNil() {
        let resolved = AppVersion.resolvedWithBuild(infoDictionary: nil)
        #expect(resolved == AppVersion.fallback)
    }
}
