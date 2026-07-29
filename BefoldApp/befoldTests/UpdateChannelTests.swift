@testable import befold
import BefoldTestSupport
import Testing

@Suite
struct UpdateChannelTests {
    @Test
    func defaultChannelIsStable() {
        let defaults = makeIsolatedDefaults(prefix: "UpdateChannelTests")
        #expect(UpdateChannel.read(from: defaults) == .stable)
    }

    @Test
    func developChannelIsReadFromDefaults() {
        let defaults = makeIsolatedDefaults(prefix: "UpdateChannelTests")
        defaults.set("develop", forKey: "UpdateChannel")
        #expect(UpdateChannel.read(from: defaults) == .develop)
    }

    @Test
    func unknownValueFallsBackToStable() {
        let defaults = makeIsolatedDefaults(prefix: "UpdateChannelTests")
        defaults.set("unknown", forKey: "UpdateChannel")
        #expect(UpdateChannel.read(from: defaults) == .stable)
    }

    @Test("stable チャネルの feedURLString は配布サイトの appcast.xml を指す")
    func stableFeedURLString() {
        #expect(UpdateChannel.stable.feedURLString ==
            "https://befold-site.tokutomi.workers.dev/appcast.xml")
    }

    @Test("develop チャネルの feedURLString は配布サイトの appcast-develop.xml を指す")
    func developFeedURLString() {
        #expect(UpdateChannel.develop.feedURLString ==
            "https://befold-site.tokutomi.workers.dev/appcast-develop.xml")
    }
}
