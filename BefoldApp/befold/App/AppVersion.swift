/// アプリのバージョン文字列。project.yml の MARKETING_VERSION と手動で同期させる
/// (SPM ビルドでは Info.plist の $(MARKETING_VERSION) 置換が行われないため、
/// CLI --version はこの定数を単一の情報源として参照する)。
enum AppVersion {
    static let current = "1.7.2"
}
