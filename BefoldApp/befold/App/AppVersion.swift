import Foundation

/// アプリのバージョン文字列。
/// `_NSGetExecutablePath` で実バイナリのパスを取得し、`.app` バンドルの Info.plist から
/// CFBundleShortVersionString を読む。バンドル外(SPM 単体ビルド等)では `fallback` を使う。
enum AppVersion {
    static let fallback = "1.7.2"

    static var current: String {
        resolved(infoDictionary: currentBundleInfoDictionary())
    }

    static func resolved(infoDictionary: [String: Any]?) -> String {
        if let version = infoDictionary?["CFBundleShortVersionString"] as? String,
           !version.isEmpty,
           !version.hasPrefix("$(")
        {
            return version
        }
        return fallback
    }

    /// 実行ファイルパス(`Contents/MacOS/<exe>`)から、その親の `.app` バンドルのパスを返す。
    static func bundlePath(fromExecutablePath executablePath: String) -> String {
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
    static func actualExecutablePath() -> String? {
        var bufSize: UInt32 = 0
        _NSGetExecutablePath(nil, &bufSize)
        var buf = [CChar](repeating: 0, count: Int(bufSize))
        guard _NSGetExecutablePath(&buf, &bufSize) == 0 else { return nil }
        guard let resolved = realpath(&buf, nil) else { return String(cString: buf) }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
