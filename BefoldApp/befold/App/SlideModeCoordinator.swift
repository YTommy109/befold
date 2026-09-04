/// プレゼン用スライドモードの出入りを 1 箇所に集めた協調手順(TASK-585)。
///
/// 真値(`FileListModel.isSlideMode`)の更新・サイドバー幅の適用・フォーカス移動は
/// **順序に意味がある**。状態を先に決めてから幅を変えないと、ヘッダーが 1 フレームだけ
/// 広いまま描かれる。この順序をメニューアクションと「畳んだときの解除」の 2 箇所に
/// 書くと、片方だけ直る形が作れてしまうため、手順そのものをここへ畳む。
///
/// `enum` にして状態を持たせない。持ってよい状態は真値の 1 つだけで、それは
/// `FileListModel` にある。
@MainActor
enum SlideModeCoordinator {
    /// スライドモードを切り替える。View メニューとヘッダーのアイコンの両方がここを通る。
    static func toggle(model: FileListModel, collapsible: (any SidebarCollapsible)?) {
        setEnabled(!model.isSlideMode, model: model, collapsible: collapsible)
    }

    /// スライドモードを明示的に設定する。
    ///
    /// - Parameter collapsible: 幅の適用先。畳んだときの解除経路では、既に幅を
    ///   戻せない状態でも真値だけは確実に落とす必要があるため省略可能にしてある。
    static func setEnabled(
        _ enabled: Bool, model: FileListModel, collapsible: (any SidebarCollapsible)?
    ) {
        guard model.isSlideMode != enabled else { return }
        model.setSlideMode(enabled)
        collapsible?.setSlideMode(enabled)
        if enabled {
            // これがこのモードの目的そのもの。カーソルキーでファイルを送れるようにする。
            model.tableFocuser.focus()
        }
    }
}
