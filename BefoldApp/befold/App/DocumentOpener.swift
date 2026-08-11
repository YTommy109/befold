import AppKit
import BefoldCLI
import BefoldKit

/// URL をビューアウィンドウで開く唯一の入口。
///
/// 「開く」要求は CLI・Recent メニュー・Dock へのドロップ・参照クリック・ファイル選択パネル・
/// Quick Open と入口が多い。解決(実 FS アクセス)と逐次化の作法をここへ集約し、
/// 呼び出し側は経路を問わず同じ順序保証を受け取る。
@MainActor
final class DocumentOpener {
    private let windowManager: ViewerWindowManager
    private let activeViewer: ActiveViewerProvider.Provide

    /// - Parameters:
    ///   - windowManager: ウィンドウ生成先。全ウィンドウで共有する 1 個を渡す
    ///     (既定値を持たせない。渡し忘れがコンパイルエラーにならず別インスタンスになるため)。
    ///   - activeViewer: ファイル選択パネルの初期ディレクトリを決めるための現在のビューア。
    init(windowManager: ViewerWindowManager, activeViewer: @escaping ActiveViewerProvider.Provide) {
        self.windowManager = windowManager
        self.activeViewer = activeViewer
    }

    /// 指定 URL のファイルをビューアウィンドウで開く(DocumentController・Recent メニューからも呼ばれる)。
    /// ディレクトリが渡された場合は、フォルダー内最初のファイルを開く(CLI シム経由の想定)。
    /// 拡張子を問わずウィンドウは開かれ、未対応の内容ならビューア側でプレースホルダー表示する。
    func openViewer(for url: URL) {
        Task { await openViewer(for: url, options: CLIOpenOptions()) }
    }

    /// 参照クリック由来のオープン。disposition/relativeTo をそのまま ViewerWindowManager へ通す。
    func openViewer(for url: URL, disposition: OpenDisposition, relativeTo sourceWindow: NSWindow?) {
        Task {
            await openViewer(
                for: url, options: CLIOpenOptions(),
                disposition: disposition, relativeTo: sourceWindow
            )
        }
    }

    /// CLI から渡されたパス群を、表示オプション付きでそれぞれ別ウィンドウに開く。
    /// `--hidden-files`/`--no-hidden-files` はウィンドウ単位ではなくアプリ全体の設定のため、先に一度だけ反映する。
    /// パス無し起動でここへ来るのは `--hidden-files` 単独のときだけ(それ以外の表示オプションは
    /// 対象の文書を要するため CLI のパース段階で弾かれる = `CLIOpenOptions.requiresPaths`)。
    func openPaths(_ paths: [String], options: CLIOpenOptions) {
        if let showHiddenFiles = options.showHiddenFiles {
            windowManager.setHiddenFiles(showHiddenFiles)
        }
        openSequentially(paths.map { URL(fileURLWithPath: $0) }, options: options)
    }

    /// 複数の URL を、渡された順にウィンドウが出るよう逐次に開く。
    /// **複数の URL を開く入口はここ 1 本に揃える。** 1 件ずつ `openViewer(for:)` を呼ぶと
    /// 呼び出しごとに Task が張られ、解決(実 FS アクセス)の完了順でウィンドウ順序が入れ替わる。
    func openSequentially(_ urls: [URL], options: CLIOpenOptions = CLIOpenOptions()) {
        guard !urls.isEmpty else { return }
        Task { await SequentialOpener.open(urls) { await openViewer(for: $0, options: options) } }
    }

    /// ファイル選択パネルを表示し、選択されたファイルをビューアで開く。
    /// 初期ディレクトリはキーウィンドウが表示中のファイルのディレクトリ、
    /// 無ければ（未オープン含む）ホームディレクトリを使う。
    func presentOpenPanel() {
        let controller = activeViewer()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.directoryURL = OpenPanelDirectoryResolver.resolve(
            currentFileDirectory: controller?.fileURL.deletingLastPathComponent(),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            // 複数選択は選択順にウィンドウが出る必要がある。1 件ずつ openViewer(for:) を
            // 呼ぶと呼び出しごとに Task が張られ、順序が任意になる(openSequentially の doc)。
            self?.openSequentially(panel.urls)
        }
    }

    /// ディレクトリ判定とオープン対象の解決は実 FS の存在確認・列挙を伴い、ネットワーク
    /// ボリューム上ではウィンドウを出す前に停止しうる。解決だけメインアクターの外へ逃がし、
    /// ウィンドウ生成は戻ってから行う。
    private func openViewer(
        for url: URL, options: CLIOpenOptions,
        disposition: OpenDisposition = .currentTab, relativeTo sourceWindow: NSWindow? = nil
    ) async {
        let resolved = await Task.detached {
            (isDirectory: DirectoryLister.isDirectory(url), target: DirectoryLister.resolveFileToOpen(at: url))
        }.value
        let isDirectory = resolved.isDirectory
        guard let target = resolved.target else {
            presentNoFileAlert()
            return
        }
        windowManager.openViewer(
            for: target, options: options, disposition: disposition, relativeTo: sourceWindow,
            forceSidebarVisible: isDirectory
        )
    }

    private func presentNoFileAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "cli.folder.noFile", bundle: .l10n)
        alert.runModal()
    }
}
