import Foundation

/// CLI から起動中の befold インスタンスへ転送される要求。
///
/// Codable 適合はワイヤ表現(CLIRequestWire)の唯一の情報源でもある。
/// 要求の種別やオプションを増やすときは、この型と CLIOpenOptions の定義だけを変えれば
/// 送受の両側に自動で反映される。
public enum CLIRequest: Equatable, Codable, Sendable {
    /// パスを開く要求(`befold <path>`)。
    case open(paths: [String], options: CLIOpenOptions)
    /// パスをブックマークする要求(`befold --bookmark <path>`)。
    case bookmark(paths: [String])
}
