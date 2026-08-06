import BefoldKit
import Foundation

/// アプリのバージョン文字列。
/// `_NSGetExecutablePath` で実バイナリのパスを取得し、`.app` バンドルの Info.plist から
/// CFBundleShortVersionString / CFBundleVersion を読む。バンドル外(SPM 単体ビルド等)では
/// `fallback` を使う。
public enum AppVersion {
    public static let fallback = "1.12.1"

    /// バージョン文字列が SemVer のプレリリース（ハイフン接尾辞）かどうか。
    /// dev リリースは `release.yml` がタグ名 `v1.4.10-dev.N` から MARKETING_VERSION を
    /// 注入するため、実行時にこの接尾辞で dev ビルドを判別できる。
    public static func isPrerelease(_ version: String) -> Bool {
        version.contains("-")
    }

    /// マーケティングバージョンのみ(例: `1.9.1-dev.5`)。
    public static var current: String {
        resolved(infoDictionary: currentBundleInfoDictionary())
    }

    /// ビルド番号付き(例: `1.9.1-dev.5 (801)`)。GUI の About パネル表記と同体裁。
    /// CLI(`--version`)はこちらを使い、GUI とバージョン表記を揃える。
    public static var currentWithBuild: String {
        resolvedWithBuild(infoDictionary: currentBundleInfoDictionary())
    }

    public static func resolved(infoDictionary: [String: Any]?) -> String {
        VersionFormatting.shortVersion(infoDictionary: infoDictionary) ?? fallback
    }

    /// `resolved` の短縮バージョンに CFBundleVersion を括弧付きで付す。
    /// ビルド番号が取得できない場合は短縮バージョンのみを返す(`VersionFormatting` に委譲)。
    public static func resolvedWithBuild(infoDictionary: [String: Any]?) -> String {
        VersionFormatting.versionString(
            short: resolved(infoDictionary: infoDictionary),
            build: VersionFormatting.buildNumber(infoDictionary: infoDictionary)
        )
    }

    /// 実行ファイルパス(`Contents/MacOS/<exe>`)から、その親の `.app` バンドルのパスを返す。
    public static func bundlePath(fromExecutablePath executablePath: String) -> String {
        URL(fileURLWithPath: executablePath)
            .deletingLastPathComponent() // MacOS
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // xxx.app
            .path
    }

    private static func currentBundleInfoDictionary() -> [String: Any]? {
        if let executablePath = actualExecutablePath() {
            let bundle = Bundle(path: bundlePath(fromExecutablePath: executablePath))
            if let info = bundle?.infoDictionary { return info }
        }
        return Bundle.main.infoDictionary
    }

    /// `_NSGetExecutablePath` で実行ファイルの実パスを取得する。
    /// `argv[0]` はシェルが入力どおりにセットするため素のコマンド名("befold")では
    /// `realpath` が失敗する。この API は argv[0] に依存せず常に正しいパスを返す。
    public static func actualExecutablePath() -> String? {
        var bufSize: UInt32 = 0
        _NSGetExecutablePath(nil, &bufSize)
        var buf = [CChar](repeating: 0, count: Int(bufSize))
        guard _NSGetExecutablePath(&buf, &bufSize) == 0 else { return nil }
        guard let resolved = realpath(&buf, nil) else {
            return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
