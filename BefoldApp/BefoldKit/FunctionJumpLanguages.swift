import Foundation

/// 文書内ジャンプの「関数・型の定義」（TASK-485.4）が対応する言語の集合。
///
/// 値は highlight.js の言語名（`FileType.codeLanguage` が返すもの）。
/// **この集合は Swift 側でメニューを塞ぐためだけに持つ**。実際にどの行を定義と
/// みなすかは viewer 側の `DEFINITION_PATTERNS`（viewer-src/jump-providers.ts）が
/// 持っており、Swift はその中身を知らない。
///
/// 同じ集合が Swift と JS の 2 箇所に存在するため、片方だけ増やしても何も
/// 落ちない形になりうる（`HeadingJumpLevels.selectableLevels` と同じ問題）。
/// ずれは `ViewerFunctionJumpLanguageContractTests` がバンドルを読んで落とす。
public enum FunctionJumpLanguages {
    /// 対応する highlight.js 言語名。JS 側の `FUNCTION_JUMP_LANGUAGES` と一致する。
    public static let supported: Set<String> = ["swift", "python", "javascript", "typescript"]

    /// その言語で定義ジャンプを使えるか。`nil`（コード種別でない）は false。
    public static func supports(_ language: String?) -> Bool {
        guard let language else { return false }
        return supported.contains(language)
    }
}
