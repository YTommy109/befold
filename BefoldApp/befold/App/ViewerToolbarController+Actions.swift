import AppKit

/// ツールバーのボタン・セグメント・オーバーフローメニュー項目から呼ばれるアクション。
/// いずれも host への委譲のみを行う。
///
/// #selector で参照するため @objc かつ internal だが、呼び出し元は
/// `ViewerToolbarController.layout` の menuAction と生成したビューの action だけ。
/// 型の外から直接呼ばない。
extension ViewerToolbarController {
    /// モード切替セグメントコントロールの選択変更を受けて呼ばれる。
    /// 差分表示中に差分セグメントを押し直した場合だけ、モード選択ではなく
    /// レイアウト切替として扱う。「すでに差分だったか」は host の状態で判定する
    /// (sender.selectedSegment は AppKit がクリック時点で更新済みのため、
    /// 押す前の状態を知る手掛かりにならない)。
    @objc func modeSegmentChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard ModeSegments.all.indices.contains(index), let host else { return }
        switch ModeSegments.action(for: ModeSegments.all[index], current: host.effectiveDisplayMode) {
        case .toggleDiffLayout: host.toggleDiffLayout(sender)
        case let .select(mode): host.setDisplayMode(mode)
        }
    }

    /// 行番号ボタン・メニュー表現の共通アクション。host へトグルを委譲する。
    @objc func lineNumbersItemClicked(_ sender: Any?) {
        host?.toggleLineNumbers(sender)
    }

    /// ブックマークボタン・メニュー表現の共通アクション。host へトグルを委譲する。
    @objc func bookmarkItemClicked(_ sender: Any?) {
        host?.toggleBookmark(sender)
    }

    /// 戻るアイテムのメニュー表現から呼ばれる。
    @objc func goBackFromMenu(_ sender: Any?) {
        host?.navigateHistory(by: -1)
    }

    /// 進むアイテムのメニュー表現から呼ばれる。
    @objc func goForwardFromMenu(_ sender: Any?) {
        host?.navigateHistory(by: 1)
    }
}
