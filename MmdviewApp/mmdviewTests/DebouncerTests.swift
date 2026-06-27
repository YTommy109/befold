import Testing
import Foundation
@testable import mmdview

@Suite
struct DebouncerTests {
    @Test
    func firesAfterDelay() async {
        await confirmation { confirm in
            let queue = DispatchQueue(label: "test.debouncer")
            let debouncer = Debouncer(delay: 0.1, queue: queue)

            debouncer.schedule {
                confirm()
            }

            try? await Task.sleep(for: .seconds(0.5))
        }
    }

    @Test
    func coalescesRapidCalls() async {
        nonisolated(unsafe) var callCount = 0
        let queue = DispatchQueue(label: "test.debouncer")
        let debouncer = Debouncer(delay: 0.1, queue: queue)

        for _ in 0..<5 {
            debouncer.schedule {
                callCount += 1
            }
        }

        try? await Task.sleep(for: .seconds(0.5))
        #expect(callCount == 1)
    }

    @Test
    func cancelPreventsExecution() async {
        nonisolated(unsafe) var fired = false
        let queue = DispatchQueue(label: "test.debouncer")
        let debouncer = Debouncer(delay: 0.1, queue: queue)

        debouncer.schedule {
            fired = true
        }
        debouncer.cancel()

        try? await Task.sleep(for: .seconds(0.3))
        #expect(!fired)
    }
}
