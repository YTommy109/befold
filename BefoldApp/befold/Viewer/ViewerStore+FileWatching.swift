import BefoldKit
import Foundation

/// 対象ファイルの監視まわり。開く／監視を張り替える／rename を追従する／
/// 削除を（グレース期間つきで）確定する、という「どのファイルを見ているか」の管理を担う。
/// 読み込みそのものは `ViewerStore+Loading` の loadContent へ委ねる。
@MainActor
extension ViewerStore {
    /// 指定 URL のファイルを開き、ファイル監視を開始する。
    /// 既に別のファイルを開いている場合は、先に監視を停止してから切り替える。
    func openFile(_ url: URL) {
        fileGoneWatchdog.cancel()
        fileWatcher?.stop()
        // 差分は表示中ファイルに紐づくため、対象が変わった時点で捨てる。
        // 取得は非同期で、着地までの間ここに残っていると前のファイルの差分が
        // 新しいファイルの内容として描画される。
        diffContent = .unavailable
        setPendingURL(url)
        pendingFileType = FileType(url: url)
        loadContent()

        fileWatcher = makeWatcher(url, watcherDebounceDelay, { [weak self] in
            self?.loadContent()
        }, { [weak self] newURL in
            self?.handleRename(to: newURL)
        })
    }

    /// 注入された fileReader を通したファイル存在確認(ディレクトリを含む)。
    /// ウィンドウ層(ViewerWindowController)の switch/rename/リンク遷移の存在ガードが
    /// 静的な DefaultFileReader を直接叩かず、store と同一の fileReader を共有できるようにする
    /// (テストで InMemoryFileReader を注入した store 経由でモック化するため)。
    func fileExists(at url: URL) -> Bool {
        fileReader.fileExists(at: url)
    }

    /// 注入された fileReader を通した「存在する通常ファイル(ディレクトリでない)」判定。
    /// 用途は fileExists(at:) と同じく存在ガードの fileReader 共有。
    func isExistingFile(at url: URL) -> Bool {
        fileReader.isExistingFile(at: url)
    }

    /// 監視対象ファイルの rename / move を反映する。
    /// コンテンツの再読込を予約したうえでウィンドウ側へ通知する。公開 filePath / fileType は
    /// apply() で content と同時にのみ更新する(ViewerStore の pendingURL / pendingFileType 参照)。
    private func handleRename(to newURL: URL) {
        let oldURL = pendingURL
        setPendingURL(newURL)
        pendingFileType = FileType(url: newURL)
        loadContent()
        if let oldURL {
            onFileRenamed?(oldURL, newURL)
        }
    }

    /// グレース期間後にファイルの不在を再確認し、確定したら onFileGone を発火する。
    /// 待機と張り替えは `FileGoneWatchdog` が持つ。ここは「何をもって消えたとするか」だけを渡す。
    func scheduleFileGone() {
        fileGoneWatchdog.schedule { [weak self] in
            guard let self, let filePath = contentState.filePath else { return }
            guard !fileReader.fileExists(at: filePath.resolvingSymlinksInPath()) else { return }
            onFileGone?()
        }
    }
}
