@testable import befold
import Foundation
import Testing

/// 複数 URL のオープンが「渡された順」を保つことを検証する。
///
/// 実際の順序崩れは、1 件ごとに Task を張って解決(実 FS アクセス)の完了順で
/// ウィンドウが出ることで起きる。ここでは解決の遅さを待ち時間で模し、
/// **遅い 1 件目が速い 2 件目に追い越されない**ことを見る。
/// SequentialOpener が並行実行へ書き換えられたらこのテストが落ちる。
@Suite
@MainActor
struct SequentialOpenerTests {
    private let urls = (1 ... 3).map { URL(fileURLWithPath: "/mock/\($0).md") }

    @Test("解決に時間がかかる URL があっても、渡された順に開く")
    func opensInGivenOrderEvenWhenEarlierItemsAreSlow() async {
        var opened: [URL] = []
        // 先頭ほど長く待たせる。並行に走れば待ち時間の短い後続が先に着地する。
        let delays: [UInt64] = [30_000_000, 10_000_000, 1_000_000]

        await SequentialOpener.open(urls) { url in
            let index = urls.firstIndex(of: url) ?? 0
            try? await Task.sleep(nanoseconds: delays[index])
            opened.append(url)
        }

        #expect(opened == urls)
    }

    @Test("空の入力では 1 度も開かない")
    func emptyInputOpensNothing() async {
        var openedCount = 0

        await SequentialOpener.open([]) { _ in openedCount += 1 }

        #expect(openedCount == 0)
    }
}
