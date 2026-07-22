import Foundation

/// アプリのバージョン文字列。
/// xcodebuild でビルドされた.appバンドル(CI の dev/release ビルド含む)では、実行時に
/// Info.plist(CFBundleShortVersionString、CIがタグから注入する実際の値)を優先して参照する。
/// `Bundle.main` は `/usr/local/bin/befold`(CLIInstaller が設置する symlink)経由の起動では
/// symlink を辿れずバンドルを解決できないため使わず、実行ファイルの実パス(symlink解決後)から
/// バンドルを探す。SPM 単体ビルド等でバンドルが見つからない場合は、`fallback`
/// (project.yml の MARKETING_VERSION と手動で同期させる)を使う。
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
        guard let argv0 = CommandLine.arguments.first,
              let resolvedPath = realpath(argv0, nil)
        else {
            return Bundle.main.infoDictionary
        }
        defer { free(resolvedPath) }
        let executablePath = String(cString: resolvedPath)
        let bundle = Bundle(path: bundlePath(fromExecutablePath: executablePath))
        return bundle?.infoDictionary ?? Bundle.main.infoDictionary
    }
}
