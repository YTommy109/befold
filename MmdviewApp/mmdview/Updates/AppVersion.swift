/// セマンティックバージョン("1.2.3" / "v1.2.3")のパースと比較。
/// 桁数が異なる場合は 0 埋めで比較する(1.2 == 1.2.0、1.2 < 1.2.1)。
struct AppVersion: Comparable, Sendable {
    let components: [Int]

    init?(_ string: String) {
        var body = string
        if body.hasPrefix("v") {
            body.removeFirst()
        }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            parsed.append(value)
        }
        components = parsed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
