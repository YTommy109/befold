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
    /// 次の表示で中央へ置くか。`.centered` は毎回、記憶する方針は保存値が無いときの初回だけ。
    private var centersOnNextShow = true
    private var placement: HostedPanelPlacement = .centered

    /// - Parameters:
    ///   - resizable: リサイズ可否。About と設定は固定サイズ、Help 配下は可変。
    ///   - contentSize: 初期サイズ。nil ならホスティングビューの固有サイズに任せる
    ///     (設定ウィンドウは中身に合わせて縮む)。
    ///   - minSize: 最小サイズ。nil なら AppKit の既定に任せる。
    ///   - placement: 開く位置の方針。既定値は置かない(パネルを足すたびに選ばせる)。
    convenience init(
        rootView: some View,
        title: String,
        resizable: Bool,
        placement: HostedPanelPlacement,
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
        self.placement = placement
        if let name = placement.autosaveName {
            centersOnNextShow = !Self.restoreFrame(of: window, named: name, keepsSize: placement.keepsSize)
            window.setFrameAutosaveName(name)
        }
    }

    /// 保存済みの枠を復元する。`keepsSize` が false なら位置(左上)だけを採り、サイズは生成時のまま。
    /// - Returns: 保存値があって復元したか。
    private static func restoreFrame(of window: NSWindow, named name: String, keepsSize: Bool) -> Bool {
        let initialSize = window.frame.size
        guard window.setFrameUsingName(name) else { return false }
        if !keepsSize {
            let restored = window.frame
            let origin = NSPoint(x: restored.minX, y: restored.maxY - initialSize.height)
            window.setFrame(NSRect(origin: origin, size: initialSize), display: false)
        }
        return true
    }

    func showAndActivate() {
        if centersOnNextShow { window?.center() }
        if placement.autosaveName != nil { centersOnNextShow = false }
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

/// パネルを開く位置の方針(TASK-656)。
/// 読むだけのパネルは毎回中央、操作するパネルはユーザーが置いた場所を覚える。
enum HostedPanelPlacement: Equatable {
    /// 開くたびに画面中央へ置く。
    case centered
    /// 最後の位置とサイズを覚える(frame autosave)。
    case rememberFrame(autosaveName: String)
    /// 最後の位置だけを覚え、サイズは中身に合わせる。
    case rememberPosition(autosaveName: String)

    var autosaveName: String? {
        switch self {
        case .centered: nil
        case let .rememberFrame(name), let .rememberPosition(name): name
        }
    }

    var keepsSize: Bool {
        if case .rememberFrame = self { return true }
        return false
    }
}

/// AppDelegate が単一インスタンスで保持するパネルの種類。
/// 「保持スロット」と「生成方法」をこのキーで対応づけ、ウィンドウごとの
/// `controller ?? Make(); store; toggle()` の繰り返しをなくす。
enum HostedPanel: Hashable {
    case about
    case settings
    /// ブックマークの管理(別名・削除・フォルダー)。文書の窓ではないので `ViewerWindowKind` には乗せない。
    case bookmarks
    case featureOverview
    case keyboardShortcuts
    case aiIntegration
    case ossLicenses
}

extension HostedPanel {
    /// 開く位置の方針(TASK-656)。操作するパネルだけがユーザーの置いた場所を覚え、
    /// 読むだけのパネルは毎回中央。網羅的な switch なので、パネルを足すと方針の選択を迫られる。
    var placement: HostedPanelPlacement {
        switch self {
        case .bookmarks:
            .rememberFrame(autosaveName: "BookmarkManagerWindow")
        case .settings:
            // 固定サイズで中身に合わせて縮むので、覚えるのは位置だけ。
            .rememberPosition(autosaveName: "SettingsWindow")
        case .about, .featureOverview, .keyboardShortcuts, .aiIntegration, .ossLicenses:
            .centered
        }
    }
}
