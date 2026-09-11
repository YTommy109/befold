import AppKit
import BefoldKit
import Foundation

/// "Open Recent" 履歴を UserDefaults に永続化するストア。
/// macOS 標準の Recent Documents(sharedfilelistd)はコード署名アイデンティティに
/// 紐付いており、ad-hoc 署名のリリースではアップデートのたびに別アプリ扱いとなって
/// 履歴が破棄される。メニューは自前描画のため、履歴データもアプリ側で保持する。
@MainActor
final class RecentDocumentsStore {
    private static let defaultsKey = "RecentDocumentPaths"

    private let recentPaths: PathListDefaults

    /// システム管理の履歴(Dock のアプリアイコン → 最近使った項目)への通知。
    ///
    /// **自前の履歴と同じ関数の中で呼ぶ。** 開いた / rename の通知は、かつて呼び出し側
    /// 2 箇所がそれぞれ `NSDocumentController` を直接叩いており、片方だけに除外を足すと
    /// 2 つの履歴が食い違う形になっていた(TASK-610)。差し替えられるのはテストが
    /// 「通知しないこと」を観測するためで、プロダクトコードから既定以外を渡す先は無い。
    /// Clear Menu の `clearRecentDocuments` は入口が `MainMenuCoordinator` の 1 つだけなので、
    /// ここへは折り込んでいない。
    private let noteSystemRecent: @MainActor (URL) -> Void

    init(
        defaults: UserDefaults = .standard,
        maximumCount: Int = 25,
        noteSystemRecent: @escaping @MainActor (URL) -> Void = {
            NSDocumentController.shared.noteNewRecentDocumentURL($0)
        }
    ) {
        recentPaths = PathListDefaults(defaults: defaults, key: Self.defaultsKey, limit: maximumCount)
        self.noteSystemRecent = noteSystemRecent
    }

    /// 履歴の URL を新しい順で返す。
    func recentURLs() -> [URL] {
        recentPaths.urls
    }

    /// ファイルが開かれたことを記録する。既存の同一パスは先頭へ移動し、
    /// 上限を超えた分は古い方から捨てる。
    ///
    /// `kind` は**必須**で受ける(TASK-610)。履歴に残さない窓の種別があるため、
    /// デフォルト引数にすると新しい呼び出し元が黙って「残す」側に倒れる。
    func noteOpened(_ url: URL, kind: ViewerWindowKind) {
        guard kind.recordsUsageHistory else { return }
        recentPaths.moveToFront(url)
        noteSystemRecent(url)
    }

    /// rename / move を履歴に反映する。
    ///
    /// 位置を保った置き換えは種別を問わず行う——既に載っている項目が消えたパスを
    /// 指したまま残るのを防ぐためで、これは「積む」ことにはならない。先頭への昇格と
    /// システムへの通知は `noteOpened` と同じ 1 つの判定に任せる(TASK-610)。
    func noteRenamed(from oldURL: URL, to newURL: URL, kind: ViewerWindowKind) {
        recentPaths.replace(oldURL, with: newURL)
        noteOpened(newURL, kind: kind)
    }

    /// 履歴を全て消す(Clear Menu)。空配列を保存するため、以降の seedIfNeeded は無効になる。
    func clear() {
        recentPaths.replaceAll(with: [])
    }

    /// 一度も記録がない初回起動時のみ、システム管理の履歴(移行元)を取り込む。
    func seedIfNeeded(with urls: [URL]) {
        guard !recentPaths.hasStoredValue else { return }
        recentPaths.replaceAll(withURLs: urls)
    }
}
