import Foundation

final class FileWatcher: @unchecked Sendable {
    private let resolvedPath: URL
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private let debouncer: Debouncer
    private let onChange: @MainActor @Sendable () -> Void
    private let queue: DispatchQueue

    init(path: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.resolvedPath = path.resolvingSymlinksInPath()
        self.queue = DispatchQueue(label: "com.degino.mmdview.filewatcher", qos: .utility)
        self.debouncer = Debouncer(delay: 0.2, queue: queue)
        self.onChange = onChange
        startMonitors()
    }

    private func startMonitors() {
        startDirectoryMonitor()
        startFileMonitor()
    }

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
                self.fileSource = nil
            }
            self.scheduleNotify()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.fileSource = source
    }

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
            if self.fileSource == nil {
                self.startFileMonitor()
            }
            self.scheduleNotify()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.dirSource = source
    }

    private func scheduleNotify() {
        let onChange = self.onChange
        debouncer.schedule {
            Task { @MainActor in
                onChange()
            }
        }
    }

    func stop() {
        fileSource?.cancel()
        dirSource?.cancel()
        debouncer.cancel()
    }

    deinit {
        stop()
    }
}
