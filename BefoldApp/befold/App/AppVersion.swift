import Foundation

/// アプリのバージョン文字列。
/// xcodebuild でビルドされた.appバンドル(CI の dev/release ビルド含む)では、実行時に
/// Bundle.main の Info.plist(CFBundleShortVersionString、CIがタグから注入する実際の値)を
/// 優先して参照する。SPM 単体ビルドでは Info.plist がバンドル化されず参照できないため、
/// `fallback`(project.yml の MARKETING_VERSION と手動で同期させる)を使う。
enum AppVersion {
    static let fallback = "1.7.2"

    static var current: String {
        resolved(infoDictionary: Bundle.main.infoDictionary)
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
}
