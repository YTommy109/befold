import Foundation

extension Bundle {
    /// Localizable.xcstrings を含むバンドル。
    /// swift build / swift test ではリソースが Bundle.module に入り、
    /// xcodebuild のアプリバンドルでは Bundle.main に入る差を吸収する。
    static var l10n: Bundle {
        #if SWIFT_PACKAGE
            .module
        #else
            .main
        #endif
    }
}
