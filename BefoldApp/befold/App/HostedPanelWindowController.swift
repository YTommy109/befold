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
    /// 次の表示で中央へ置くか。`.centered` は毎回、`.remember` は保存値が無いときの初回だけ。
    private var centersOnNextShow = true

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
        if case let .remember(name) = placement {
            // リサイズ不可の窓では AppKit が保存値の左上だけを戻し、サイズは中身のまま保つ(TASK-657 で実測)。
            centersOnNextShow = !window.setFrameUsingName(name)
            window.setFrameAutosaveName(name)
        }
    }

    func showAndActivate() {
        if centersOnNextShow { window?.center() }
        // 保存名を持つ窓は、以後ユーザーが置いた位置を保つ。
        centersOnNextShow = window?.frameAutosaveName.isEmpty ?? true
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
    /// 最後の枠を覚える(frame autosave)。リサイズ可能な窓は位置とサイズ、
    /// リサイズ不可の窓は位置だけが戻る(サイズは中身に従う)。
    case remember(autosaveName: String)
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
            .remember(autosaveName: "BookmarkManagerWindow")
        case .settings:
            // リサイズ不可なので、戻るのは位置だけ(サイズは中身に合わせる)。
            .remember(autosaveName: "SettingsWindow")
        case .about, .featureOverview, .keyboardShortcuts, .aiIntegration, .ossLicenses:
            .centered
        }
    }
}
