import Foundation

/// `"<short> (<build>)"` 形式のバージョン文字列を組み立てる単一情報源。
///
/// GUI の About パネルは AppKit が Info.plist の CFBundleShortVersionString と
/// CFBundleVersion を自動整形して同じ体裁で表示する。その体裁を CLI(`--version`)や
/// QuickLook バッジでも再現するため、両モジュールから import できる最下層の
/// BefoldKit に共通フォーマッタを置く。
public enum VersionFormatting {
    /// `short` に `build` を括弧付きで付す。`build` が nil・空文字・未置換プレースホルダ
    /// (`"$(...)"`)の場合は括弧を付けず `short` のみを返す。これによりビルド番号が
    /// 取得できない状況でも空括弧 `"1.9.0 ()"` やクラッシュにならない。
    public static func versionString(short: String, build: String?) -> String {
        if let build, !build.isEmpty, !build.hasPrefix("$(") {
            return "\(short) (\(build))"
        }
        return short
    }
}
