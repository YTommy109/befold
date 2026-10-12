/// GUI アプリ本体(befold.app)の同一性を表す定数。
///
/// befold-cli は `/usr/local/bin/befold` の symlink 経由で起動されるため、`Bundle.main` は
/// symlink の置き場所(`/usr/local/bin`)に解決され、Info.plist もバンドル ID も得られない。
/// GUI アプリを指すバンドル ID が必要な箇所は `Bundle.main` ではなくここを参照する。
public enum AppBundle {
    /// project.yml の befold ターゲットの `PRODUCT_BUNDLE_IDENTIFIER` と一致させる
    /// (ProjectYmlPackagingTests でドリフトを検知する)。
    public static let identifier = "com.degino.befold"
}
