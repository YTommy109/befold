import Foundation

protocol FileWatching: Sendable {
    func stop()
}

/// ファイル変更を DispatchSource で監視し、変更時にコールバックを呼ぶ。
/// ファイル削除後の再作成（アトミック保存）にも対応するため、
/// ファイル本体とディレクトリの両方を監視する。
final class FileWatcher: FileWatching, @unchecked Sendable {
    private let resolvedPath: URL
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private let debouncer: Debouncer
    private let onChange: @MainActor @Sendable () -> Void
    private let queue: DispatchQueue

    init(path: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        resolvedPath = path.resolvingSymlinksInPath()
        queue = DispatchQueue(label: "com.degino.mmdview.filewatcher", qos: .utility)
        debouncer = Debouncer(delay: 0.2, queue: queue)
        self.onChange = onChange
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

    // MARK: - File Monitoring

    /// ファイルの書き込み・削除・リネームを監視する。
    /// 削除時はソースを解放し、ディレクトリ監視側で再作成を検知する。
    private func startFileMonitor() {
        fileSource?.cancel()
        fileSource = nil

        let fd = open(resolvedPath.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                source.cancel()
                fileSource = nil
            }
            scheduleNotify()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileSource = source
    }

    // MARK: - Directory Monitoring

    /// 親ディレクトリの変更を監視し、ファイルが再作成された場合にファイル監視を再開する。
    private func startDirectoryMonitor() {
        let dirPath = resolvedPath.deletingLastPathComponent().path
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            if fileSource == nil {
                startFileMonitor()
            }
            scheduleNotify()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        dirSource = source
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
            fileSource?.cancel()
            fileSource = nil
            dirSource?.cancel()
            dirSource = nil
            debouncer.cancel()
        }
    }

    deinit {
        stop()
    }
}
