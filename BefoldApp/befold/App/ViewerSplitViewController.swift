import AppKit
import SwiftUI

/// 既存ウィンドウのサイドバー開閉を、ジェネリック型パラメータを消して操作するためのプロトコル。
/// CLI の `--sidebar`/`--no-sidebar` をパス無し起動で既存ウィンドウへ適用する際に使う。
@MainActor
protocol SidebarCollapsible: AnyObject {
    func setSidebarCollapsed(_ collapsed: Bool)
    /// サイドバーが畳まれているか。⌘← の有効判定に使う（畳んでいるなら移り先が無い）。
    var isSidebarCollapsed: Bool { get }
    /// スライドモードの幅を適用／解除する（TASK-585）。**真偽値はここでは保持しない**
    /// （真値は `FileListModel.isSlideMode`）。
    func setSlideMode(_ enabled: Bool)
}

final class ViewerSplitViewController<Sidebar: View, Content: View>: NSSplitViewController {
    static var defaultSidebarWidth: CGFloat {
        220
    }

    /// 通常モードでのサイドバー幅の下限。スライドモードはこれを一時的に下回る。
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
    /// スライドモードへ入る直前のサイドバー幅。抜けるときにここへ戻す。
    /// スライドモード中だけ値を持つ。
    private var thicknessBeforeSlideMode: CGFloat?
    private let initialCollapsed: Bool
    private let onCollapsedChange: (Bool) -> Void
    private let onSidebarDidReveal: () -> Void
    private let onSidebarDidHide: () -> Void

    /// `onSidebarDidHide` に既定値を持たせない。これは `onSidebarDidReveal` の対で、
    /// 渡し忘れると「開いた要求が保留のまま、閉じた後に成立する」形が静かに戻る
    /// (TASK-563)。渡し忘れをコンパイルエラーにする。
    init(
        sidebar: Sidebar, content: Content, initialCollapsed: Bool = true,
        onCollapsedChange: @escaping (Bool) -> Void = { _ in },
        onSidebarDidReveal: @escaping () -> Void = {},
        onSidebarDidHide: @escaping () -> Void
    ) {
        self.initialCollapsed = initialCollapsed
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
        setAutosaveEnabled(true)
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

    override func toggleSidebar(_ sender: Any?) {
        let wasCollapsed = sidebarItem.isCollapsed
        super.toggleSidebar(sender)
        onCollapsedChange(sidebarItem.isCollapsed)
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

    /// スライドモードの幅を適用／解除する（TASK-585）。真偽値は保持しない。
    ///
    /// **autosave を止めてから幅を変える。** `autosaveName` が生きていると AppKit が
    /// 任意のタイミングでスライドモードの細幅を保存キーへ書き出し、`viewWillAppear` の
    /// 「記憶があれば上書きしない」規則がそれを固定化して、次に開く窓のサイドバーが
    /// 細いままになる。この形なら、スライドモードのまま終了しても細幅は焼かれない。
    ///
    /// **min／max を先に変えてから `setPosition` する。** 逆順だと `setPosition` の値が
    /// そのときの min／max で clamp されて効かない。
    func setSlideMode(_ enabled: Bool) {
        if enabled {
            guard thicknessBeforeSlideMode == nil else { return }
            thicknessBeforeSlideMode = sidebarItem.viewController.view.frame.width
            setAutosaveEnabled(false)
            sidebarItem.minimumThickness = SidebarSlideMetrics.width
            sidebarItem.maximumThickness = SidebarSlideMetrics.width
            splitView.setPosition(SidebarSlideMetrics.width, ofDividerAt: 0)
        } else {
            guard let restored = thicknessBeforeSlideMode else { return }
            thicknessBeforeSlideMode = nil
            sidebarItem.minimumThickness = Self.minimumSidebarWidth
            sidebarItem.maximumThickness = Self.maximumSidebarWidth
            splitView.setPosition(restored, ofDividerAt: 0)
            setAutosaveEnabled(true)
        }
    }

    /// `autosaveName` を触る**唯一の場所**。外から設定できないよう private にする。
    /// ここが 1 箇所であることが、スライドモード中に幅が焼き込まれない担保になる。
    private func setAutosaveEnabled(_ enabled: Bool) {
        splitView.autosaveName = enabled ? Self.autosaveName : nil
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

    /// 望む開閉状態と現在が異なるときだけ toggleSidebar を再利用して切り替える。
    /// これにより状態永続化(onCollapsedChange)とフォーカス移動の挙動を一本化する。
    func setSidebarCollapsed(_ collapsed: Bool) {
        guard sidebarItem.isCollapsed != collapsed else { return }
        toggleSidebar(nil)
    }
}
