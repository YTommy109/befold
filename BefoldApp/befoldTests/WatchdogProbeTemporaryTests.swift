import Foundation
import Testing

@MainActor
struct WatchdogProbeTemporaryTests {
    @Test("main thread blocked on purpose")
    func blockMainThreadOnPurpose() {
        sleep(1800)
    }
}
