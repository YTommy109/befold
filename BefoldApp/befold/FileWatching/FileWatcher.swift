import Foundation

protocol FileWatching: Sendable {
    func stop()
}

/// ファイル変更を DispatchSource で監視し、変更時にコールバックを呼ぶ。
/// ファイル削除後の再作成（アトミック保存）にも対応するため、
/// ファイル本体とディレクトリの両方を監視する。
/// ファイルの rename / move を検知した場合は監視対象を新パスへ切り替え、
/// onRename で通知する。
final class FileWatcher: FileWatching, @unchecked Sendable {
    /// .rename 検知から追従判定までの待機時間。
    /// save-by-rename（旧ファイル退避 → 同パスへ新ファイル作成）では
    /// 退避直後の一瞬だけ元パスが空になるため、この間隔だけ待って
    /// 元パスへの再出現有無を見てから rename か変更かを判定する。
    /// 既定値はプロダクト用。テストは短い値を注入して所要時間を縮める。
    private let renameSettleDelay: TimeInterval

    /// 現在の監視対象パス。rename 追従で書き換わるため var。
    /// 読み書きは常にイベントハンドラと同じ監視キュー上で直列化する。
    private var resolvedPath: URL
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private let debouncer: Debouncer
    private let onChange: @MainActor @Sendable () -> Void
    private let onRename: (@MainActor @Sendable (URL) -> Void)?
    private let queue: DispatchQueue

    init(
        path: URL,
        debounceDelay: TimeInterval = 0.2,
        renameSettleDelay: TimeInterval = 0.2,
        onChange: @escaping @MainActor @Sendable () -> Void,
        onRename: (@MainActor @Sendable (URL) -> Void)? = nil
    ) {
        resolvedPath = path.resolvingSymlinksInPath()
        self.renameSettleDelay = renameSettleDelay
        queue = DispatchQueue(label: "com.degino.befold.filewatcher", qos: .utility)
        debouncer = Debouncer(delay: debounceDelay, queue: queue)
        self.onChange = onChange
        self.onRename = onRename
        // fileSource / dirSource はイベントハンドラ（監視キュー上）でも
        // 解放・再割り当てされるため、初期化時の書き込みも同じ監視キューに
        // 直列化して競合を防ぐ。init は queue が空の状態で呼ばれるので
        // queue.sync でデッドロックせず、戻り時点で監視が有効になる。
        queue.sync { startMonitors() }
    }

    private func startMonitors() {
        startDirectoryMonitor()
        startFileMonitor()
    }

    // MARK: - Monitor Helpers

    /// DispatchSource 生成の定型処理を共通化する。
    /// open(path) → fd 検査 → makeFileSystemObjectSource → handler/cancel 設定 → resume。
    private func makeMonitor(
        path: String,
        mask: DispatchSource.FileSystemEvent,
        handler: @escaping (DispatchSourceFileSystemObject) -> Void
    ) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: mask,
            queue: queue
        )
        source.setEventHandler { handler(source) }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func stopFileMonitor() {
        fileSource?.cancel()
        fileSource = nil
    }

    private func stopDirectoryMonitor() {
        dirSource?.cancel()
        dirSource = nil
    }

    // MARK: - File Monitoring

    /// ファイルの書き込み・削除・リネームを監視する。
    /// 削除時はソースを解放し、ディレクトリ監視側で再作成を検知する。
    /// リネーム時は移動後のパスを判別し、追従または削除扱いに振り分ける。
    private func startFileMonitor() {
        stopFileMonitor()

        fileSource = makeMonitor(
            path: resolvedPath.path,
            mask: [.write, .delete, .rename, .attrib],
            handler: { [weak self] source in
                guard let self else { return }
                let flags = source.data
                if flags.contains(.rename) {
                    scheduleRenameResolution(fd: source.handle)
                    return
                }
                if flags.contains(.delete) {
                    stopFileMonitor()
                }
                scheduleNotify()
            }
        )
    }

    /// ファイル本体の .rename イベントを受けて、追従判定を settle 待ち後に予約する。
    /// 判定を遅らせるのは、save-by-rename の一瞬だけ空になる元パスを
    /// 誤って move と判定しないため。fd はまだ close しない（cancel しない）ので
    /// 判定時に F_GETPATH で移動後パスを取得できる。
    private func scheduleRenameResolution(fd: Int32) {
        let originalPath = resolvedPath
        queue.asyncAfter(deadline: .now() + renameSettleDelay) { [weak self] in
            self?.resolveRename(fd: fd, originalPath: originalPath)
        }
    }

    /// settle 待ち後に rename か変更かを判定する。
    /// F_GETPATH で移動後のパスを取得し、アトミック保存・ゴミ箱移動・実 rename を判別する。
    private func resolveRename(fd: Int32, originalPath: URL) {
        // stop() 済み、または連続 rename 等で既に監視を張り直した後の遅延判定なら
        // 何もしない。fd が close 済み（別ファイルに再利用された可能性もある）の
        // まま F_GETPATH に使うのを防ぐため、現在の監視ソースの fd と一致する
        // 場合だけ判定を続行する。
        guard let source = fileSource, source.handle == fd else { return }
        let newPath = currentPath(of: fd)

        // (a) 元パスにファイルが再出現している（save-by-rename / アトミック保存）。
        //     「変更」として扱い、元パスの新ファイルを監視し直す。
        if FileManager.default.fileExists(atPath: originalPath.path) {
            stopFileMonitor()
            startFileMonitor()
            scheduleNotify()
            return
        }

        // (b) 新パスが取得でき、元パスと異なり、ゴミ箱でもなく、通知先がある
        //     → rename / move として監視対象を新パスへ切り替える。
        if let newPath, newPath.path != originalPath.path, !isInTrash(newPath), onRename != nil {
            switchToNewPath(newPath)
            return
        }

        // (c) それ以外（ゴミ箱への移動・新パス不明・onRename 未設定）→ 削除として扱う。
        stopFileMonitor()
        scheduleNotify()
    }

    /// 監視対象を新パスへ切り替える。
    /// ディレクトリ間 move では親ディレクトリも変わるため、ファイル・ディレクトリ両監視を張り直す。
    /// rename 通知の後に変更通知が来ても順序が破綻しないよう、
    /// 先に監視を張り直してから onRename を確定させる（変更通知はデバウンスされるため後着になる）。
    private func switchToNewPath(_ newPath: URL) {
        resolvedPath = newPath

        stopFileMonitor()
        stopDirectoryMonitor()
        startMonitors()

        guard let onRename else { return }
        Task { @MainActor in
            onRename(newPath)
        }
    }

    /// F_GETPATH で fd が指すファイルの現在のパスを取得する。取得できなければ nil。
    private func currentPath(of fd: Int32) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return nil }
        let path = buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.map { String(cString: $0) } ?? ""
        }
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }

    /// パスがゴミ箱内かどうか。ゴミ箱への移動は rename ではなく削除として扱う。
    private func isInTrash(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/.Trash/") || path.contains("/.Trashes/")
    }

    // MARK: - Directory Monitoring

    /// 親ディレクトリの変更を監視し、ファイルが再作成された場合にファイル監視を再開する。
    private func startDirectoryMonitor() {
        stopDirectoryMonitor()

        let dirPath = resolvedPath.deletingLastPathComponent().path
        dirSource = makeMonitor(
            path: dirPath,
            mask: [.write],
            handler: { [weak self] _ in
                guard let self else { return }
                if fileSource == nil {
                    startFileMonitor()
                }
                scheduleNotify()
            }
        )
    }

    // MARK: - Notification

    private func scheduleNotify() {
        let onChange = onChange
        debouncer.schedule {
            Task { @MainActor in
                onChange()
            }
        }
    }

    // MARK: - Lifecycle

    /// 全監視を停止しリソースを解放する。
    func stop() {
        // fileSource / dirSource へのアクセスをイベントハンドラと同じ監視キューに
        // 直列化する。stop() は MainActor（windowWillClose）または deinit からのみ
        // 呼ばれ、監視キュー上からは呼ばれないため queue.sync でデッドロックしない。
        queue.sync {
            stopFileMonitor()
            stopDirectoryMonitor()
            debouncer.cancel()
        }
    }

    deinit {
        stop()
    }
}
