import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ウィンドウのタイトルとプロキシアイコン(`representedURL`)が **提示対象** に追随することを
/// 検証する(TASK-469)。
///
/// 導出はファイル URL ではなく `FileListModel.previewTarget` が決める。ファイル URL が
/// 動く契機(生成・切替・リネーム)だけを見ていた頃は、サイドバーでフォルダーを選んで
/// 一覧を出しても直前のファイル名が残っていた。
@Suite("ウィンドウタイトルの提示対象追随")
@MainActor
struct ViewerWindowTitleTests {
    private let file = URL(fileURLWithPath: "/mock/doc.mmd")
    private let folder = URL(fileURLWithPath: "/mock/assets", isDirectory: true)

    /// 一覧に「フォルダー行 1 つとファイル行 1 つ」を流し込む。実 FS を列挙させると
    /// /mock は存在せず行が作れないため、モデルへ直接反映する(列挙結果の中身は本質でない)。
    private func applyEntries(to controller: ViewerWindowController) {
        controller.fileListModel.setEntries(
            [FileListEntry(url: folder, kind: .folder), FileListEntry(url: file, kind: .file)],
            for: controller.fileListModel.currentDirectory,
            didFailEnumeration: false
        )
    }

    @Test("フォルダー提示中はタイトルと representedURL がそのフォルダーを指す")
    func selectingFolderRetitlesWindowToFolder() {
        let controller = makeMockedViewerWindowController(
            primary: file, defaults: makeIsolatedDefaults(prefix: "WindowTitleFolder")
        )
        defer { controller.close() }
        applyEntries(to: controller)
        controller.fileListModel.selection = file
        #expect(controller.window?.title == "doc.mmd")

        controller.fileListModel.selection = folder

        #expect(controller.fileListModel.previewTarget == .folder(folder))
        #expect(controller.window?.title == "assets")
        #expect(controller.window?.representedURL?.lastPathComponent == "assets")
    }

    @Test("ファイル提示へ戻るとタイトルと representedURL がそのファイルへ戻る")
    func returningToFileRestoresFileTitle() {
        let controller = makeMockedViewerWindowController(
            primary: file, defaults: makeIsolatedDefaults(prefix: "WindowTitleFile")
        )
        defer { controller.close() }
        applyEntries(to: controller)
        controller.fileListModel.selection = folder
        #expect(controller.window?.title == "assets")

        controller.fileListModel.selection = file

        #expect(controller.fileListModel.previewTarget == .file)
        #expect(controller.window?.title == "doc.mmd")
        #expect(controller.window?.representedURL == file)
    }

    @Test("導出はファイル URL ではなく提示対象が決める(ViewerWindowChrome.applyURL)")
    func chromeDerivesTitleFromPreviewTarget() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.titled], backing: .buffered, defer: true
        )

        ViewerWindowChrome.applyURL(file, presenting: .file, to: window)
        #expect(window.title == "doc.mmd")
        #expect(window.representedURL == file)

        ViewerWindowChrome.applyURL(file, presenting: .folder(folder), to: window)
        #expect(window.title == "assets")
        #expect(window.representedURL?.lastPathComponent == "assets")

        // 一覧が届く前(未確定)は、開こうとしている文書を出す。
        ViewerWindowChrome.applyURL(file, presenting: .undetermined, to: window)
        #expect(window.title == "doc.mmd")
    }
}
