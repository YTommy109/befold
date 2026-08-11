import AppKit
import BefoldKit

/// リンク・パス参照の ctrl+クリック（右クリック）メニューの表示と、選ばれた項目の実行を担う。
///
/// **項目定義・表示・実行を 1 つの型に閉じる。** メインメニュー/ツールバー由来のアクションと違い、
/// この 3 つは 1 つの流れなので、離すと `#selector` の対応が読めなくなる。
/// `menu.popUp` の target がこの型自身なので、`@objc` アクションもここに置ける
/// （ウィンドウコントローラは NSResponder チェーンの受け口を増やさずに済む）。
///
/// 遷移そのもの（ウィンドウ内での切替・別タブ/別ウィンドウ）と相対パスの算出は
/// クロージャでウィンドウへ委譲する（循環参照を避けるため、渡す側が弱参照で捕捉する）。
@MainActor
final class ReferenceMenuPresenter: NSObject {
    /// 「相対パスをコピー」で書き込む文字列（ウィンドウ解放後は nil）。
    ///
    /// 基準ディレクトリではなく**算出済みの文字列**を受け取る。ここで基準を選ぶ形にすると、
    /// サイドバーの同名項目（`FileListModel.relativePathForCopy`）と規則が分かれて
    /// 2 つのメニューが黙って食い違うため（TASK-422。実際、以前は表示中ファイルの URL を
    /// 基準に渡していて、相対化が常に失敗し絶対パスがコピーされていた）。
    /// テストから配線を突き合わせられるよう internal にする。
    let relativePathForCopy: (URL) -> String?
    /// 解決済みパス参照を開く。
    private let openReference: (URL, OpenDisposition) -> Void
    /// 外部 URL（http/https）をブラウザで開く処理。本番では NSWorkspace 経由。
    /// テストが実ブラウザを起動せずに済むよう注入可能にしている。
    private let externalOpener: (URL) -> Void

    init(
        relativePathForCopy: @escaping (URL) -> String?,
        openReference: @escaping (URL, OpenDisposition) -> Void,
        externalOpener: @escaping (URL) -> Void
    ) {
        self.relativePathForCopy = relativePathForCopy
        self.openReference = openReference
        self.externalOpener = externalOpener
    }

    /// コンテキストメニューを表示する。
    /// 表示位置は JS の座標ではなく現在のマウス位置を使う（WKWebView の CSS ピクセルと
    /// NSView 座標の変換、ページズームの影響を避けるため）。
    func present(for url: URL, isExternal: Bool, in window: NSWindow?) {
        guard let contentView = window?.contentView,
              let location = window?.mouseLocationOutsideOfEventStream
        else { return }
        let menu = ReferenceContextMenu.makeMenu(
            for: url, isExternal: isExternal, target: self, action: #selector(performMenuAction(_:))
        )
        menu.popUp(positioning: nil, at: contentView.convert(location, from: nil), in: contentView)
    }

    /// 各項目の実行を、既存の遷移・Finder・クリップボード処理へ委譲する。
    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let invocation = sender.representedObject as? ReferenceMenuInvocation else { return }
        switch invocation.action {
        case let .open(disposition):
            // 外部 URL（http/https）はファイルビューア経路（switchFile/openFileElsewhere）に
            // ローカルパスが無く、渡すと「ファイルが見つかりません」になる。修飾キーに
            // かかわらずブラウザで開く（通常クリック・cmd+クリックと同じ扱いに揃える）。
            if invocation.isExternal {
                externalOpener(invocation.url)
            } else {
                openReference(invocation.url, disposition)
            }
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([invocation.url])
        case .copyName:
            Pasteboard.writeString(invocation.url.lastPathComponent)
        case .copyRelativePath:
            guard let path = relativePathForCopy(invocation.url) else { return }
            Pasteboard.writeString(path)
        }
    }
}
