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
    /// 変更イベントのデバウンス既定値。他コンポーネントがこの時間を前提にした
    /// 待機を行う場合は、数値をハードコードせずこの定数を参照する。
    static let defaultDebounceDelay: TimeInterval = 0.2

    /// renameSettleDelay の既定値。数値のハードコードを避けるためここで一元定義する。
    static let defaultRenameSettleDelay: TimeInterval = 0.2

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
        debounceDelay: TimeInterval = FileWatcher.defaultDebounceDelay,
        renameSettleDelay: TimeInterval = FileWatcher.defaultRenameSettleDelay,
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
        // 解放・再割り当てされるため、初期化時の書き込みも同じ監視キューへ
        // 直列化して競合を防ぐ。
        //
        // **`queue.sync` を使ってはならない。** `startMonitors` は監視対象と
        // その親ディレクトリを `open()` で開く。sync にすると、この syscall が
        // 呼び出し元（多くはメインスレッド）で同期に走り、iCloud Drive や
        // ネットワークボリュームのように open が遅い場所ではアプリ全体が
        // その間止まる（TASK-566 の実測では 3 秒のサンプル 2611/2611 が
        // メインスレッドの `open()` だった）。
        //
        // 非同期化で「init から戻ったが、まだ監視していない」区間ができる。
        // ただし **この区間は元から存在していた**——`DispatchSource.resume()` は
        // 同期に戻るが kevent のカーネル登録は非同期に完了するため、sync でも
        // 「戻り時点で監視が有効」は成立していない（`confirmWatcherArmed` の
        // doc コメントを参照）。広がった分は、監視開始の前後でファイルが
        // 変わっていた場合だけ通知して埋める（`startMonitorsAndCatchUp`）。
        queue.async { self.startMonitorsAndCatchUp() }
    }

    private func startMonitors() {
        startDirectoryMonitor()
        startFileMonitor()
    }

    /// 監視開始と、開始までの取りこぼしを埋める通知をまとめて行う。init 専用。
    ///
    /// **通知は「実際に変わったとき」だけ出す。** 無条件に出してはならない。
    /// `ViewerStore.loadContent` は呼ばれるたびに `loadGeneration` を進めるため、
    /// 開いた直後に通知すると**走行中の初回読み込みの結果が捨てられ、読み直しに
    /// なる**（世代が古くなった結果は `performLoad` の着地で破棄される）。
    /// 段階読み込み中のファイルではその分だけ初回表示が遅れる。
    ///
    /// 変化の判定は監視開始の前後で撮った `FileFingerprint`（inode・サイズ・
    /// 更新時刻）の比較で行う。埋まるのは**このブロックが動き始めてから
    /// 監視が張られるまで**——非同期化で広げた `open()` の所要時間そのもので、
    /// 遅いパスではここが支配的になる。
    ///
    /// 埋まらない区間も残る。(a) init から監視キューがこのブロックを走らせる
    /// までのディスパッチ待ち、(b) `DispatchSource.resume()` から kevent の
    /// カーネル登録が完了するまで。(b) は非同期化以前から存在していた
    /// （`confirmWatcherArmed` の doc コメントを参照）。どちらも `open()` の
    /// 待ち時間とは桁が違うため、ここでは埋めない。
    ///
    /// `stop()` が先着した場合、この通知はデバウンサー経由で予約されているため
    /// `debouncer.cancel()` が一緒に取り消す。
    private func startMonitorsAndCatchUp() {
        let before = FileFingerprint(path: resolvedPath.path)
        startMonitors()
        let after = FileFingerprint(path: resolvedPath.path)
        guard before != after else { return }
        scheduleNotify()
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

/// ファイルが「別物になったか」を安く見分けるための指紋。inode・サイズ・更新時刻を
/// 見る。内容の同一性ではなく変化の有無だけを判定するもので、内容が同じかどうかは
/// 受け手側の hash 比較（`ViewerContentState.applyDisplayState` の `isUnchanged`）が持つ。
///
/// 対象が存在しない場合も `nil` ではなく「存在しないという指紋」として扱う
/// （`exists` が false）。nil にすると「取得できなかった」と「無かった」が同じになり、
/// 削除を変化として拾えなくなる。
struct FileFingerprint: Equatable {
    let exists: Bool
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64

    init(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else {
            self = FileFingerprint(
                exists: false, inode: 0, size: 0, modifiedSeconds: 0, modifiedNanoseconds: 0
            )
            return
        }
        self = FileFingerprint(
            exists: true,
            inode: UInt64(info.st_ino),
            size: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec)
        )
    }

    private init(
        exists: Bool, inode: UInt64, size: Int64,
        modifiedSeconds: Int64, modifiedNanoseconds: Int64
    ) {
        self.exists = exists
        self.inode = inode
        self.size = size
        self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
    }
}
