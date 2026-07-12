import Foundation

#if SWIFT_PACKAGE
    public extension Bundle {
        /// BefoldKit のリソースバンドル。SPM は _BefoldKit_Resources を自動生成する。
        static let befoldKitResources: Bundle = .module
    }
#else
    /// Bundle(for:) でフレームワークバンドルを特定するためのアンカークラス。
    private final class BundleFinder {}

    public extension Bundle {
        /// BefoldKit のリソースバンドル。Xcode ビルド(framework ターゲット)では
        /// リソースはフレームワークバンドル直下に配置されるため、自身のバンドルを返す。
        static let befoldKitResources = Bundle(for: BundleFinder.self)
    }
#endif
