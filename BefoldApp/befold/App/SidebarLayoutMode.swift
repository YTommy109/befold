import Foundation

/// サイドバーの行の並べ方。
///
/// ドリルダウンは「展開集合が空」の縮退形なので、行の生成はどちらも
/// `SidebarRowBuilder.rows` の 1 本を通る(TASK-361.1)。この型が決めるのは
/// 「展開を許すか」であって、別々の描画経路を選ぶスイッチではない。
enum SidebarLayoutMode: String, Sendable, CaseIterable {
    /// 従来。1 階層ずつ降り、常に 1 ディレクトリぶんだけを表示する。
    case drillDown
    /// Finder のリスト表示相当。開閉三角でサブフォルダをその場に展開し、
    /// 複数のフォルダを同時に開いたままにできる。
    case tree

    /// 保存値・未知の文字列から読む。キーが無い/壊れているときは従来表示へ倒す。
    /// 新しい表示のほうを既定にすると、保存値を読めなかっただけで見た目が変わる。
    static func stored(_ rawValue: String?) -> SidebarLayoutMode {
        rawValue.flatMap(SidebarLayoutMode.init(rawValue:)) ?? .drillDown
    }
}
