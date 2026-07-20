import AppKit
import Foundation

/// CLI 起動時、既に起動中の befold インスタンスがあればそちらへファイルオープン要求を転送する。
/// これにより CLI 経由の起動でも、既存インスタンスのウィンドウ管理(セッション・重複オープン抑止等)を
/// そのまま利用でき、`--hidden-files` 等の表示オプションも既存インスタンスへ届けられる。
enum CLIInstanceRouter {
    /// `DistributedNotificationCenter` 経由でオープン要求を伝える通知名。
    static let openRequestNotificationName = Notification.Name("dev.befold.cli.openRequest")

    /// 自プロセス以外に起動中の befold インスタンスがあれば返す。
    @MainActor
    static func runningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// `paths`/`options` を既存インスタンスへ Distributed Notification 経由で転送する。
    @MainActor
    static func forward(paths: [String], options: CLIOpenOptions, to instance: NSRunningApplication) {
        var userInfo: [String: Any] = ["paths": paths]
        if let value = options.showHiddenFiles { userInfo["showHiddenFiles"] = value }
        if let value = options.showLineNumbers { userInfo["showLineNumbers"] = value }
        if let value = options.sourceMode { userInfo["sourceMode"] = value }
        if let value = options.sortOrder { userInfo["sortOrder"] = value.rawValue }
        DistributedNotificationCenter.default().postNotificationName(
            openRequestNotificationName, object: nil, userInfo: userInfo, deliverImmediately: true
        )
        instance.activate()
    }

    /// 受信した Distributed Notification の userInfo から paths/options を復元する。
    static func decode(userInfo: [AnyHashable: Any]?) -> (paths: [String], options: CLIOpenOptions)? {
        guard let paths = userInfo?["paths"] as? [String] else { return nil }
        var options = CLIOpenOptions()
        options.showHiddenFiles = userInfo?["showHiddenFiles"] as? Bool
        options.showLineNumbers = userInfo?["showLineNumbers"] as? Bool
        options.sourceMode = userInfo?["sourceMode"] as? Bool
        if let rawSortOrder = userInfo?["sortOrder"] as? String {
            options.sortOrder = CLISortOrderOption(rawValue: rawSortOrder)
        }
        return (paths, options)
    }
}
