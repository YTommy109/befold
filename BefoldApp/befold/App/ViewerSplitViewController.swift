import AppKit
import SwiftUI

/// 既存ウィンドウのサイドバー開閉を、ジェネリック型パラメータを消して操作するためのプロトコル。
/// CLI の `--sidebar`/`--no-sidebar` をパス無し起動で既存ウィンドウへ適用する際に使う。
@MainActor
protocol SidebarCollapsible: AnyObject {
    func setSidebarCollapsed(_ collapsed: Bool)
    /// サイドバーが畳まれているか。⌘← の有効判定に使う（畳んでいるなら移り先が無い）。
    var isSidebarCollapsed: Bool { get }
    /// 表示前も含めた、この窓の開閉状態。**表示前の窓では `isSidebarCollapsed` が初期値と
    /// 食い違う**（初期値を当てるのが viewWillAppear のため）。窓の状態を別の窓へ引き継ぐときはこちらを読む。
    var resolvedSidebarCollapsed: Bool { get }
}

final class ViewerSplitViewController<Sidebar: View, Content: View>: NSSplitViewController {
    static var defaultSidebarWidth: CGFloat {
        220
    }

    /// サイドバー幅の下限。
    static var minimumSidebarWidth: CGFloat {
        200
    }

    static var maximumSidebarWidth: CGFloat {
        480
    }

    private static var autosaveName: String {
        "ViewerSplitView"
    }

    private static var autosaveDefaultsKey: String {
        "NSSplitView Subview Frames ViewerSplitView"
    }

    private let sidebarItem: NSSplitViewItem
    private var didForceInitialCollapse = false
    /// サイドバーを開けるか(窓の種別が決める / TASK-593.2)。
    private let allowsSidebar: Bool
    private let initialCollapsed: Bool
    private let onCollapsedChange: (Bool) -> Void
    private let onSidebarDidReveal: () -> Void
    private let onSidebarDidHide: () -> Void

    /// 3 つのコールバックに既定値を持たせない。渡し忘れると、開閉が記録されない・開いても表へ
    /// フォーカスが移らない・「開いた要求が保留のまま、閉じた後に成立する」(TASK-563)形が静かに
    /// 戻る。本番の配線は `ViewerWindowAssembler.makeSidebarSplit` の 1 箇所に置く。
    init(
        sidebar: Sidebar, content: Content, initialCollapsed: Bool = true,
        allowsSidebar: Bool = true,
        onCollapsedChange: @escaping (Bool) -> Void,
        onSidebarDidReveal: @escaping () -> Void,
        onSidebarDidHide: @escaping () -> Void
    ) {
        self.initialCollapsed = initialCollapsed
        self.allowsSidebar = allowsSidebar
        self.onCollapsedChange = onCollapsedChange
        self.onSidebarDidReveal = onSidebarDidReveal
        self.onSidebarDidHide = onSidebarDidHide
        sidebarItem = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: sidebar))
        super.init(nibName: nil, bundle: nil)

        sidebarItem.minimumThickness = Self.minimumSidebarWidth
        sidebarItem.maximumThickness = Self.maximumSidebarWidth
        sidebarItem.canCollapse = true

        let contentItem = NSSplitViewItem(viewController: NSHostingController(rootView: content))

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)

        // ディバイダー位置(サイドバー幅)を起動をまたいで永続化する。
        // この autosave は開閉状態も復元するため、開閉だけは
        // viewWillAppear で明示的に決める(initialCollapsed が呼び出し側の解決結果)
        splitView.autosaveName = Self.autosaveName
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // autosave の記憶がない(初回起動)場合のみ、デフォルト幅を明示適用する。
        // 記憶がある場合は autosave の復元をそのまま尊重し、上書きしない(AC#4)。
        if UserDefaults.standard.object(forKey: Self.autosaveDefaultsKey) == nil {
            splitView.setPosition(Self.defaultSidebarWidth, ofDividerAt: 0)
        }

        // autosave の復元が開閉状態も引き継ぐため、初回表示の直前に必ず確定させる。
        // 開閉状態(記憶の引き継ぎ・CLI からの強制表示など)の解決は呼び出し側が行い、
        // ここでは initialCollapsed をそのまま適用するだけにする。
        // タブ切替や最小化復帰でも viewWillAppear は呼ばれるため、初回に限定する
        guard !didForceInitialCollapse else { return }
        didForceInitialCollapse = true
        sidebarItem.isCollapsed = initialCollapsed
    }

    /// 利用者の開閉操作。開閉したうえで保存値へ記録する。
    ///
    /// **開かせない窓ではここで止める**(TASK-593.2)。`setSidebarCollapsed(_:)` も同じガードを
    /// 持つので、CLI の `--sidebar` と `forceSidebarVisible` を含む**すべての開閉経路が止まる**。
    /// メニュー検証(⌘S の無効化)は利用者に押させないための表示側の手当てで、
    /// 実際に開かせない担保はこちら。
    ///
    /// ここで止まると `onCollapsedChange` が発火しないため、`SidebarStateStore.recordToggle`
    /// にも届かない。「種別の帰結である折りたたみを利用者の選択として保存しない」
    /// (ADR 0002)は、別のガードではなくこの構造が担保している。
    override func toggleSidebar(_ sender: Any?) {
        guard allowsSidebar else { return }
        performToggle(sender)
        onCollapsedChange(sidebarItem.isCollapsed)
    }

    /// 開閉そのものと、開閉に伴うフォーカスの後始末。記録はしない。
    private func performToggle(_ sender: Any?) {
        let wasCollapsed = sidebarItem.isCollapsed
        if Self.shouldAnimateSidebarToggle(in: view.window) {
            super.toggleSidebar(sender)
        } else {
            sidebarItem.isCollapsed.toggle()
        }
        if wasCollapsed, !sidebarItem.isCollapsed {
            // 開いた直後にサイドバー(アウトラインビュー)へフォーカスを移し、フォルダー名を
            // アクティブ(黒)表示にして矢印キー操作を可能にする(task-118)。フォーカス先の解決は
            // ViewerWindowController に委ね、ここでは開いた事実だけを通知する。
            DispatchQueue.main.async { [weak self] in
                self?.onSidebarDidReveal()
            }
        }
        // 畳んだら、まだ成立していないフォーカス要求を捨てさせる。遅れて行が描かれた
        // ときに、閉じたはずのサイドバーがフォーカスを奪わないようにする(TASK-563)。
        if !wasCollapsed, sidebarItem.isCollapsed {
            onSidebarDidHide()
        }
    }

    /// サイドバーの開閉をアニメーションさせてよいか。**画面に出ていない窓ではさせない。**
    ///
    /// 出ていない窓では AppKit の開閉アニメーション(`NSAnimation`)が完了せず、呼び出しごとに
    /// libdispatch のワーカースレッドを 1 本塞いだまま残す。全体テストでは窓を作るテストが
    /// 約 50 本をそのまま積み、スレッドの上限(64)の手前で動くことになる(TASK-673。
    /// 実測: 54 本 → 0 本)。見せるものが無いので、アニメーションなしで確定させる。窓が無い(まだ載っていない)ときは従来どおり AppKit に任せる。
    static func shouldAnimateSidebarToggle(in window: NSWindow?) -> Bool {
        window?.isVisible ?? true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}

extension ViewerSplitViewController: SidebarCollapsible {
    var isSidebarCollapsed: Bool {
        sidebarItem.isCollapsed
    }

    var resolvedSidebarCollapsed: Bool {
        didForceInitialCollapse ? sidebarItem.isCollapsed : initialCollapsed
    }

    /// CLI とフォルダーオープンからの開閉。望む状態と現在が異なるときだけ切り替える。
    /// **記録しない。** どちらもこの起動限りの指定で、利用者が操作した値ではない
    /// (`SidebarDisplayState.applyCLIOverride` と同じ区別)。
    func setSidebarCollapsed(_ collapsed: Bool) {
        guard allowsSidebar, sidebarItem.isCollapsed != collapsed else { return }
        performToggle(nil)
    }
}
