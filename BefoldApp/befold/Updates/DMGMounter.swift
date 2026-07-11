import Foundation

/// DMG のマウント/アンマウントを抽象化するプロトコル。
protocol DMGMounting: Sendable {
    func mount(dmgAt dmgURL: URL) throws -> URL
    func detach(mountPoint: URL)
}

/// hdiutil を使った DMG のマウント/アンマウント。
struct DMGMounter: DMGMounting, Sendable {
    struct MountFailed: Error {}

    /// DMG をマウントしてマウントポイントを返す。
    /// Gatekeeper の警告を避けるため、事前に quarantine 属性を除去する。
    /// `Process` 実行でブロックするため、呼び出し側で `Task.detached` に載せること。
    func mount(dmgAt dmgURL: URL) throws -> URL {
        removeQuarantine(from: dmgURL)
        let output = try run("/usr/bin/hdiutil", ["attach", dmgURL.path, "-nobrowse", "-plist"])
        guard let mountPoint = Self.mountPoint(fromPlist: output) else {
            throw MountFailed()
        }
        return mountPoint
    }

    func detach(mountPoint: URL) {
        _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
    }

    /// `hdiutil attach -plist` の出力からマウントポイントを取り出す。
    static func mountPoint(fromPlist data: Data) -> URL? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]]
        else {
            return nil
        }
        for entity in entities {
            if let path = entity["mount-point"] as? String {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func removeQuarantine(from url: URL) {
        _ = try? run("/usr/bin/xattr", ["-d", "com.apple.quarantine", url.path])
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MountFailed()
        }
        return data
    }
}
