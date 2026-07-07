/// セマンティックバージョン("1.2.3" / "v1.2.3" / "1.2.3-dev.1")のパースと比較。
/// 桁数が異なる場合は 0 埋めで比較する(1.2 == 1.2.0、1.2 < 1.2.1)。
/// プレリリース識別子は SemVer 準拠: 正式版 > プレリリース版。
struct AppVersion: Comparable, Sendable {
    let components: [Int]
    let prerelease: [String]?

    init?(_ string: String) {
        var body = string
        if body.hasPrefix("v") {
            body.removeFirst()
        }
        let prereleaseStart = body.firstIndex(of: "-")
        let versionPart = prereleaseStart.map { body[body.startIndex ..< $0] }
            ?? body[body.startIndex...]
        let parts = versionPart.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            parsed.append(value)
        }
        components = parsed

        if let start = prereleaseStart {
            let suffix = body[body.index(after: start)...]
            guard !suffix.isEmpty else { return nil }
            prerelease = suffix.split(separator: ".").map(String.init)
        } else {
            prerelease = nil
        }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0 ..< count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        // 同じ数値部分: 正式版 > プレリリース版
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false // lhs は正式版、rhs はプレリリース → lhs > rhs
        case (_, nil): return true // lhs はプレリリース、rhs は正式版 → lhs < rhs
        case let (lp?, rp?):
            let preCount = max(lp.count, rp.count)
            for index in 0 ..< preCount {
                guard index < lp.count else { return true }
                guard index < rp.count else { return false }
                if let li = Int(lp[index]), let ri = Int(rp[index]) {
                    if li != ri { return li < ri }
                } else {
                    if lp[index] != rp[index] { return lp[index] < rp[index] }
                }
            }
            return false
        }
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
