import AppKit
import SwiftUI

/// SwiftUI ビューを `NSHostingController` に載せた単一インスタンスのパネルウィンドウ。
/// About・設定・Help 配下の各ウィンドウが共有する「開閉トグル」の実装元。
///
/// 各ウィンドウで実際に異なるのはタイトル・中身のビュー・サイズ・リサイズ可否だけなので、
/// それらを引数に取り、表示/トグルのロジックはここ 1 箇所に置く。
@MainActor
final class HostedPanelWindowController: NSWindowController {
    /// 最前面判定のシーム。既定は実ウィンドウの isKeyWindow だが、テストから注入できるようにする。
    var isFrontmost: () -> Bool = { false }

    /// - Parameters:
    ///   - resizable: リサイズ可否。About と設定は固定サイズ、Help 配下は可変。
    ///   - contentSize: 初期サイズ。nil ならホスティングビューの固有サイズに任せる
    ///     (設定ウィンドウは中身に合わせて縮む)。
    ///   - minSize: 最小サイズ。nil なら AppKit の既定に任せる。
    convenience init(
        rootView: some View,
        title: String,
        resizable: Bool,
        contentSize: NSSize? = nil,
        minSize: NSSize? = nil
    ) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = title
        window.styleMask = resizable ? [.titled, .closable, .resizable] : [.titled, .closable]
        if let contentSize { window.setContentSize(contentSize) }
        if let minSize { window.minSize = minSize }
        self.init(window: window)
        isFrontmost = { [weak window] in window?.isKeyWindow ?? false }
    }

    func showAndActivate() {
        window?.center()
        showWindow(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// 最前面なら閉じ、そうでなければ開く/前面化する(同じメニュー項目の再選択で引っ込む)。
    func toggle() {
        if isFrontmost() {
            window?.close()
        } else {
            showAndActivate()
        }
    }
}

/// AppDelegate が単一インスタンスで保持するパネルの種類。
/// 「保持スロット」と「生成方法」をこのキーで対応づけ、ウィンドウごとの
/// `controller ?? Make(); store; toggle()` の繰り返しをなくす。
enum HostedPanel: Hashable {
    case about
    case settings
    case featureOverview
    case keyboardShortcuts
    case aiIntegration
    case ossLicenses
}
