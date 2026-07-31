import Foundation

extension Bundle {
    /// アプリ本体に同梱したリソース(Localizable.xcstrings, ヘルプ用のサンプルファイルなど)を含むバンドル。
    /// swift build / swift test ではリソースが Bundle.module に入り、
    /// xcodebuild のアプリバンドルでは Bundle.main に入る差を吸収する。
    static var appResources: Bundle {
        #if SWIFT_PACKAGE
            .module
        #else
            .main
        #endif
    }

    /// Localizable.xcstrings を含むバンドル。
    static var l10n: Bundle {
        appResources
    }
}
