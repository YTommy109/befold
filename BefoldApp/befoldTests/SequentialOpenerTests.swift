@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// 複数 URL のオープンが「渡された順」を保つことを検証する。
///
/// 実際の順序崩れは、1 件ごとに Task を張って解決(実 FS アクセス)の完了順で
/// ウィンドウが出ることで起きる。ここでは解決の遅さを URL ごとのゲートで模し、
/// **遅い 1 件目が速い 2 件目に追い越されない**ことを見る。
/// SequentialOpener が並行実行へ書き換えられたらこのテストが落ちる。
@Suite(testTimeLimit())
@MainActor
struct SequentialOpenerTests {
    private let urls = (1 ... 3).map { URL(fileURLWithPath: "/mock/\($0).md") }

    @MainActor
    private final class Log {
        var started: [URL] = []
        var opened: [URL] = []
    }

    @Test("解決に時間がかかる URL があっても、渡された順に開く")
    func opensInGivenOrderEvenWhenEarlierItemsAreSlow() async {
        let log = Log()
        let gates = urls.map { _ in AsyncGate() }
        let urls = urls
        let opening = Task {
            await SequentialOpener.open(urls) { url in
                log.started.append(url)
                await gates[urls.firstIndex(of: url) ?? 0].wait()
                log.opened.append(url)
            }
        }

        // 先頭が解決待ちに入ってから、後ろから順に解決を終わらせる。
        // 並行に走れば、先に解決した後続が先に着地する。
        await waitForDeliveryOnMainActor { !log.started.isEmpty }
        for gate in gates.reversed() {
            gate.open()
        }
        await opening.value

        #expect(log.opened == urls)
    }

    @Test("空の入力では 1 度も開かない")
    func emptyInputOpensNothing() async {
        var openedCount = 0

        await SequentialOpener.open([]) { _ in openedCount += 1 }

        #expect(openedCount == 0)
    }
}
