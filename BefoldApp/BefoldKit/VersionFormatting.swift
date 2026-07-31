import Foundation

/// `"<short> (<build>)"` 形式のバージョン文字列を組み立てる単一情報源。
///
/// GUI の About パネルは AppKit が Info.plist の CFBundleShortVersionString と
/// CFBundleVersion を自動整形して同じ体裁で表示する。その体裁を CLI(`--version`)や
/// QuickLook バッジでも再現するため、両モジュールから import できる最下層の
/// BefoldKit に共通フォーマッタを置く。
public enum VersionFormatting {
    /// Info.plist のバージョンキー。読み取り側でリテラルを書かないようここに集約する。
    private enum InfoKey {
        static let shortVersion = "CFBundleShortVersionString"
        static let build = "CFBundleVersion"
    }

    /// `short` に `build` を括弧付きで付す。`build` が nil・空文字・未置換プレースホルダ
    /// (`"$(...)"`)の場合は括弧を付けず `short` のみを返す。これによりビルド番号が
    /// 取得できない状況でも空括弧 `"1.9.0 ()"` やクラッシュにならない。
    public static func versionString(short: String, build: String?) -> String {
        if let build = usableValue(build) {
            return "\(short) (\(build))"
        }
        return short
    }

    /// Info.plist から整形済みの `"<short> (<build>)"` を組み立てる。
    /// 短縮バージョンが取れない場合は nil を返し、フォールバックの決定は呼び出し側に委ねる
    /// (CLI は既知の版へ、QuickLook バッジは版なし表記へ、と落とし方が異なるため)。
    public static func versionString(infoDictionary: [String: Any]?) -> String? {
        guard let short = shortVersion(infoDictionary: infoDictionary) else { return nil }
        return versionString(short: short, build: buildNumber(infoDictionary: infoDictionary))
    }

    /// Info.plist の CFBundleShortVersionString。取れない場合は nil。
    public static func shortVersion(infoDictionary: [String: Any]?) -> String? {
        usableValue(infoDictionary?[InfoKey.shortVersion] as? String)
    }

    /// Info.plist の CFBundleVersion。取れない場合は nil。
    public static func buildNumber(infoDictionary: [String: Any]?) -> String? {
        usableValue(infoDictionary?[InfoKey.build] as? String)
    }

    /// バージョン値として使えるものだけを通す。空文字と未置換プレースホルダ(`"$(...)"`)は
    /// 値が取れなかったのと同じ扱いにする(SPM 単体ビルドでは Xcode の変数展開が走らない)。
    private static func usableValue(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
