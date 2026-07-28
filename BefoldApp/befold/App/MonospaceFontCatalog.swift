import AppKit

/// システムの等幅フォント名一覧を提供する。整形（重複除去・ソート）は純粋関数として切り出す。
enum MonospaceFontCatalog {
    /// 整形のみ（テスト対象）。
    static func names(from rawFamilyNames: [String]) -> [String] {
        Array(Set(rawFamilyNames)).sorted()
    }

    /// システムから等幅フォントファミリー名を集める（GUI 用、テスト対象外）。
    @MainActor
    static func systemMonospaceFamilyNames() -> [String] {
        let manager = NSFontManager.shared
        let raw = manager.availableFontFamilies.filter { family in
            guard let members = manager.availableMembers(ofFontFamily: family) else { return false }
            // メンバのいずれかが固定幅トレイトを持てば等幅ファミリーとみなす。
            return members.contains { member in
                guard member.count >= 4, let traits = member[3] as? UInt else { return false }
                return NSFontTraitMask(rawValue: traits).contains(.fixedPitchFontMask)
            }
        }
        return names(from: raw)
    }
}
