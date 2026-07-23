@testable import BefoldCLI
import Foundation
import Testing

@Suite
struct CLIInstanceRouterDecodeTests {
    @Test("全オプション付き userInfo を decode できる")
    func decodesAllOptions() {
        let userInfo: [AnyHashable: Any] = [
            "paths": ["/tmp/a.mmd", "/tmp/b.md"],
            "requestID": "test-id",
            "showHiddenFiles": true,
            "showLineNumbers": false,
            "sourceMode": true,
            "sortOrder": "alphabetical",
        ]

        let result = CLIInstanceRouter.decode(userInfo: userInfo)

        #expect(result != nil)
        #expect(result?.paths == ["/tmp/a.mmd", "/tmp/b.md"])
        #expect(result?.options.showHiddenFiles == true)
        #expect(result?.options.showLineNumbers == false)
        #expect(result?.options.sourceMode == true)
        #expect(result?.options.sortOrder == .alphabetical)
    }

    @Test("オプションなしの userInfo を decode するとデフォルト値になる")
    func decodesMinimalUserInfo() {
        let userInfo: [AnyHashable: Any] = [
            "paths": ["/tmp/a.mmd"],
        ]

        let result = CLIInstanceRouter.decode(userInfo: userInfo)

        #expect(result != nil)
        #expect(result?.paths == ["/tmp/a.mmd"])
        #expect(result?.options.showHiddenFiles == nil)
        #expect(result?.options.showLineNumbers == nil)
        #expect(result?.options.sourceMode == nil)
        #expect(result?.options.sortOrder == nil)
    }

    @Test("paths キーがなければ nil を返す")
    func returnsNilWithoutPaths() {
        let userInfo: [AnyHashable: Any] = [
            "requestID": "test-id",
        ]

        let result = CLIInstanceRouter.decode(userInfo: userInfo)

        #expect(result == nil)
    }

    @Test("nil の userInfo は nil を返す")
    func returnsNilForNilUserInfo() {
        let result = CLIInstanceRouter.decode(userInfo: nil)

        #expect(result == nil)
    }

    @Test("requestID のラウンドトリップ")
    func requestIDRoundTrip() {
        let userInfo: [AnyHashable: Any] = [
            "paths": ["/tmp/a.mmd"],
            "requestID": "abc-123",
        ]

        let id = CLIInstanceRouter.requestID(from: userInfo)

        #expect(id == "abc-123")
    }

    @Test("requestID がなければ nil")
    func requestIDMissingReturnsNil() {
        let userInfo: [AnyHashable: Any] = [
            "paths": ["/tmp/a.mmd"],
        ]

        let id = CLIInstanceRouter.requestID(from: userInfo)

        #expect(id == nil)
    }
}
