import AppKit
import BefoldKit

// MARK: - File Navigation

/// このウィンドウが**どのファイルを提示しているか**を移す操作——ファイル切替・
/// リネーム追随・フォルダー移動・戻る/進む——を受け持つ。
///
/// 移した先の表示状態(倍率・スクロール位置・表示モード)をどう決めるかは
/// `ViewerWindowController+Presentation.swift` の担当で、ここはその呼び出し順だけを持つ。
/// 一覧の選択同期と履歴の記録は `SidebarNavigator` へ委譲する。
@MainActor
extension ViewerWindowController {
    /// CLI の `--sidebar`/`--no-sidebar` から、この既存ウィンドウのサイドバー開閉を設定する。
    func setSidebarCollapsed(_ collapsed: Bool) {
        sidebarCollapsible?.setSidebarCollapsed(collapsed)
    }

    /// このウィンドウをキーウィンドウにして前面へ出す。
    func focusWindow() {
        window?.makeKeyAndOrderFront(nil)
    }

    /// サイドバーで別フォルダーへ移動する。詳細は SidebarNavigator に委譲する。
    func navigateToFolder(_ url: URL) {
        sidebar.navigateToFolder(url)
    }

    /// サイドバーの戻る/進む・履歴メニューから呼ばれる。offset 負=戻る / 正=進む。
    func navigateHistory(by offset: Int) {
        sidebar.navigateHistory(by: offset)
    }

    /// サイドバーで別ファイルが選択されたときにウィンドウの表示対象を切り替える。
    /// ファイル切替の実処理のみ担い、選択同期・履歴記録は SidebarNavigator へ委譲する。
    func switchFile(to newURL: URL) {
        let oldURL = fileURL
        guard newURL.normalizedPathKey != oldURL.normalizedPathKey else { return }
        referenceCoordinator.warm(forFileAt: newURL)
        switch performFileSwitch(to: newURL) {
        case .switched:
            sidebar.syncAfterSwitch(to: newURL)
        case .failed:
            sidebar.restoreSelection(to: oldURL)
        }
    }

    /// switchFile と履歴適用が共有するファイル切替の実処理。
    /// 切替先ファイルの保存済みビューモードの復元、URL 更新、コンテンツ読込、
    /// ズーム適用、コールバック通知を行う。
    /// 操作中(アクティブ)のウィンドウを最優先するため、切替先が別ウィンドウで開いていても
    /// そのまま自ウィンドウを切り替える(他ウィンドウの前面化はしない)。存在しない場合のみ
    /// 状態を変更せず .failed を返し、アラートを表示する。
    @discardableResult
    func performFileSwitch(to newURL: URL) -> FileSwitchOutcome {
        guard store.fileExists(at: newURL) else {
            presentReferenceNotFound(url: newURL)
            return .failed
        }
        let oldURL = fileURL
        saveScrollPositionBeforeTransition()
        applyDisplayMode(perFileState.displayMode.restoredDisplayMode(for: newURL))
        applyURLToWindow(newURL)
        // fileExists を確認済みなので store.openFile が予約した非同期読み込みは必ず完了に達し、
        // その時点で onContentReloaded → refreshToolbarState() が発火する
        // (読み込み完了までは切替前の表示状態が残る)。ここでの明示呼び出しは不要。
        store.openFile(newURL)
        // 提示開始(ファイル切替)。applyDisplayMode の後に呼ぶこと。復元するスクロール位置は
        // 切替先の表示モードに紐付くキーから引くため、モードが確定している必要がある。
        beginPresentingDocument(at: newURL)
        delegate?.viewerWindow(self, didSwitchFileFrom: oldURL, to: newURL)
        return .switched
    }

    /// ファイルの rename / move をウィンドウに反映する。
    /// リネームは同一ファイルの改名であり、内容・表示倍率・ビューモードは原則保持する。
    func handleRename(from oldURL: URL, to newURL: URL) {
        guard newURL.normalizedPathKey != oldURL.normalizedPathKey else { return }
        applyURLToWindow(newURL)

        // 実体は同じファイルなので旧パスの表示状態(倍率・表示モード・スクロール位置)を
        // 新パスへまとめて引き継ぐ(旧パスはもう存在しない)。
        perFileState.migrate(from: oldURL, to: newURL)
        // 描画状態(描画済みミラー・JS 側の文書パス)も同じ同期区間で新パスへ追随させる。
        // 呼ばないと、リネーム再描画がファイル切替として扱われてスクロール位置が
        // 提示開始時の保存値へ巻き戻り(TASK-401)、再描画確定までのスクロール通知が
        // migrate 済みの旧パスのキーへ保存される(TASK-393)。
        webViewCommands.noteRename(from: oldURL, to: newURL)
        // 内容は不変なのでビューモードは維持する。ただし対応形式が変わり
        // (例: .md → .png)そのモードが成立しなくなる場合は降格する。
        // store.handleRename が予約した非同期読み込みの完了後に onContentReloaded が
        // 発火してツールバーが追従するため、ここでの明示的な
        // refreshToolbarState() 呼び出しは不要
        // (resetSourceMode() が走る場合は applySourceMode 内で再同期される)。
        // 降格の規則は DisplayModeStore.supportedDisplayMode に 1 つだけ置く。ここで
        // 「supportsSourceMode でなければレンダリングへ戻す」と書き下すと、コード種別の
        // 差分表示まで巻き添えで落ちる(同じ判定を 2 箇所に持つと片方だけ直る)。
        // 引き継ぐのは保存値ではなく「いま表示中のモード」。保存値を読み直すと、
        // 永続化されていないライブなモード(CLI --source/--preview のこの起動限りの
        // 上書き)がリネームで破棄される。
        applyDisplayMode(perFileState.displayMode.supportedDisplayMode(displayMode, for: newURL))
        moveSidebarToDirectoryIfNeeded(of: newURL)
        delegate?.viewerWindow(self, didRenameFrom: oldURL, to: newURL)
        sidebar.applyRename(from: oldURL, to: newURL)
    }

    /// リネーム先が別フォルダーなら、サイドバーの表示ディレクトリもそちらへ移す。
    private func moveSidebarToDirectoryIfNeeded(of newURL: URL) {
        let newDir = newURL.deletingLastPathComponent()
        if newDir.normalizedPathKey != fileListModel.currentDirectory.normalizedPathKey {
            fileListModel.currentDirectory = newDir
        }
        sidebar.refreshFileList()
    }

    /// ウィンドウのタイトルと representedURL を新しい URL に合わせて更新する。
    /// 実処理は `ViewerWindowChrome`(器の責務)へ委譲する。
    func applyURLToWindow(_ newURL: URL) {
        guard let window else { return }
        ViewerWindowChrome.applyURL(newURL, to: window)
    }
}
