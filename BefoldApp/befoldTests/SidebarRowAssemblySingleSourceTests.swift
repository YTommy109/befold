import Foundation
import Testing

/// 「サイドバーの行の組み立ては 1 箇所」という規則を、呼び出し元の個数で固定する
/// (TASK-442.1)。
///
/// この規則は以前 `SidebarExpansion` の doc コメントに書いてあるだけだった。実態は
/// 2 箇所で、`DirectoryLister` が「展開集合が空」の縮退形で行を組み、それを
/// `SidebarNavigator.applyRows` が `kind == .parentNavigation` で分解し直して
/// もう一度組んでいた(1 回の列挙で組み立てが 2 回走っていた)。
///
/// 分解の往復自体は `applyRows` が `DirectoryListing`(行に畳む前の材料)を受ける形へ
/// 変えたことで構造的に塞がっている——行配列を渡そうとするとコンパイルが通らない。
/// 一方「別の場所でもう一度畳む」ほうは型では止まらないため、ここで数える。
///
/// 増やしてよい場合(畳む契機が本当に増えた場合)は、`DirectoryListing.rows` の doc を
/// 先に更新し、ここの期待値も合わせて動かすこと。無言で増やすとこのテストが落ちる。
@Suite
struct SidebarRowAssemblySingleSourceTests {
    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // befoldTests
        .deletingLastPathComponent() // BefoldApp
        .appendingPathComponent("befold")

    /// befold ターゲット配下の Swift ファイル一覧。
    private static func swiftFiles() throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: keys) else {
            throw AssemblyError.sourceRootUnreadable
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// `expression(` を **呼んでいる** 行を、ファイル名 → 件数で数える。
    /// 宣言行(`func <末尾の名前>`)とコメント行(`//` / `///` で始まる行)は除く。
    private static func callSites(of expression: String) throws -> [String: Int] {
        let name = expression.split(separator: ".").last.map(String.init) ?? expression
        var counts: [String: Int] = [:]
        for file in try swiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let calls = source.split(separator: "\n").filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { return false }
                guard !trimmed.contains("func \(name)") else { return false }
                return trimmed.contains("\(expression)(")
            }
            guard !calls.isEmpty else { continue }
            counts[file.lastPathComponent] = calls.count
        }
        return counts
    }

    @Test("行を畳む SidebarRowBuilder.rows の呼び出し元は DirectoryListing の 1 箇所だけ")
    func rowBuilderHasExactlyOneCallSite() throws {
        // ここが 2 件になると、同じ列挙結果に対して組み立てが 2 回走る形へ戻る。
        // 新しい畳み込みが要るように見えたら、まず DirectoryListing.rows の引数
        // (material / showsDisclosure)で表せないかを疑うこと。
        #expect(try Self.callSites(of: "SidebarRowBuilder.rows") == ["DirectoryListing.swift": 1])
    }

    @Test("畳んだ行を FileListModel へ反映するのは applyRows の 1 箇所だけ")
    func setEntriesHasExactlyOneCallSite() throws {
        // 反映点が増えると、展開の材料を渡し忘れた行配列がサイドバーへ入る経路ができる
        // (ドリルダウンのままの一覧が、ツリー表示のはずの窓に出る)。
        // FileListModel.swift 自身は宣言だけなので callSites には現れない。
        #expect(try Self.callSites(of: "setEntries") == ["SidebarTreePresenter.swift": 1])
    }

    private enum AssemblyError: Error {
        case sourceRootUnreadable
    }
}
