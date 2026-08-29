import Foundation
import Testing

/// ADR 0002「文書の状態の規則」1 ——「保存値を読むのは窓がその文書を提示し始めるときだけ」——
/// を、呼び出し元の個数で固定する。
///
/// この規則は以前 `ViewerWindowController.swift` 1 ファイル内の `private` が守っていた。
/// 責務ごとの型へ分割した際に internal へ上がり、befold ターゲットのどこからでも
/// 呼べるようになったため、代わりにソース走査で契機を数える(TASK-411 / TASK-441)。
///
/// 増やしてよい場合(提示開始の契機が本当に増えた場合)は、ADR 0002 の当該節を先に更新し、
/// ここの期待値も合わせて動かすこと。無言で増やすとこのテストが落ちる。
@Suite
struct ViewerWindowPresentationEntryPointTests {
    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // befoldTests
        .deletingLastPathComponent() // BefoldApp
        .appendingPathComponent("befold")

    /// befold ターゲット配下の Swift ファイル一覧。
    private static func swiftFiles() throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: keys) else {
            throw EntryPointError.sourceRootUnreadable
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// `name` を **呼んでいる** 行を、ファイル名 → 件数で数える。
    /// 宣言行(`func name`)とコメント行(`//` で始まる行)は除く。
    private static func callSites(of name: String) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for file in try swiftFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let calls = source.split(separator: "\n").filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { return false }
                guard !trimmed.contains("func \(name)") else { return false }
                return trimmed.contains("\(name)(")
            }
            guard !calls.isEmpty else { continue }
            counts[file.lastPathComponent] = calls.count
        }
        return counts
    }

    @Test("保存値を読む「提示開始」の呼び出し元はオープンとファイル切替の 2 つだけ")
    func beginPresentingDocumentHasExactlyTwoCallSites() throws {
        // モード切替(setDisplayMode)は 3 つ目の契機だが、位置のキーが (パス, モード) 粒度で
        // あるため beginPresentingDocument ではなく restoredScrollPosition を直接引く。
        let expected = [
            // 2 件の内訳: init(オープン契機)と、ViewerDocumentPresenter への委譲 1 行。
            // 委譲は契機ではないが、契機と同じ名前で呼ぶことで「入口はこの名前だけ」を保つ。
            "ViewerWindowController.swift": 2,
            "ViewerWindowController+FileNavigation.swift": 1, // performFileSwitch(ファイル切替)
        ]
        #expect(try Self.callSites(of: "beginPresentingDocument") == expected)
    }

    @Test("退場側スクロール位置の確定保存は、書き換え前の 2 経路からだけ呼ばれる")
    func saveScrollPositionBeforeTransitionHasExactlyTwoCallSites() throws {
        let expected = [
            "ViewerWindowController+FileNavigation.swift": 1, // performFileSwitch
            "ViewerDocumentPresenter.swift": 1, // setDisplayMode
            "ViewerWindowController.swift": 1, // ViewerDocumentPresenter への委譲
        ]
        #expect(try Self.callSites(of: "saveScrollPositionBeforeTransition") == expected)
    }

    /// 窓の生存期間だけの記憶は**窓ごとに 1 個**でなければならない（TASK-565）。
    /// `AppStores` など全ウィンドウ共有の場所で生成されると、閉じた窓の位置・モードが
    /// 他の窓へ漏れ、永続化をやめた意味が消える。生成箇所を 1 つに固定して構造で守る。
    @Test("窓の記憶を生成するのは ViewerDocumentPresenter の 1 箇所だけ")
    func windowPresentationMemoryHasExactlyOneConstructionSite() throws {
        let expected = ["ViewerDocumentPresenter.swift": 1]
        #expect(try Self.callSites(of: "WindowPresentationMemory") == expected)
    }

    private enum EntryPointError: Error {
        case sourceRootUnreadable
    }
}
