import Foundation

public enum AppVersion {
    public static let fallback = "1.7.2"

    public static var current: String {
        resolved(infoDictionary: currentBundleInfoDictionary())
    }

    public static func resolved(infoDictionary: [String: Any]?) -> String {
        if let version = infoDictionary?["CFBundleShortVersionString"] as? String,
           !version.isEmpty,
           !version.hasPrefix("$(")
        {
            return version
        }
        return fallback
    }

    public static func bundlePath(fromExecutablePath executablePath: String) -> String {
        URL(fileURLWithPath: executablePath)
            .deletingLastPathComponent() // MacOS
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // xxx.app
            .path
    }

    private static func currentBundleInfoDictionary() -> [String: Any]? {
        if let executablePath = actualExecutablePath() {
            let bundle = Bundle(path: bundlePath(fromExecutablePath: executablePath))
            if let info = bundle?.infoDictionary { return info }
        }
        return Bundle.main.infoDictionary
    }

    public static func actualExecutablePath() -> String? {
        var bufSize: UInt32 = 0
        _NSGetExecutablePath(nil, &bufSize)
        var buf = [CChar](repeating: 0, count: Int(bufSize))
        guard _NSGetExecutablePath(&buf, &bufSize) == 0 else { return nil }
        guard let resolved = realpath(&buf, nil) else {
            return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
