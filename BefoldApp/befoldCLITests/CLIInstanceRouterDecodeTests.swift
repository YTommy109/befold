@testable import BefoldCLI
import Foundation
import Testing

@Suite
struct CLIInstanceRouterDecodeTests {
    /// `.open` の paths/options を取り出す。種別が違えば nil を返す。
    private func openPayload(_ request: CLIRequest?) -> (paths: [String], options: CLIOpenOptions)? {
        guard case let .open(paths, options) = request else { return nil }
        return (paths, options)
    }

    @Test("全オプション付き userInfo を decode できる")
    func decodesAllOptions() {
        let userInfo: [AnyHashable: Any] = [
            "paths": ["/tmp/a.mmd", "/tmp/b.md"],
            "requestID": "test-id",
            "showHiddenFiles": true,
            "showLineNumbers": false,
            "sourceMode": true,
            "showSidebar": false,
            "sortOrder": "alphabetical",
        ]

        let result = openPayload(CLIInstanceRouter.decode(userInfo: userInfo))

        #expect(result != nil)
        #expect(result?.paths == ["/tmp/a.mmd", "/tmp/b.md"])
        #expect(result?.options.showHiddenFiles == true)
        #expect(result?.options.showLineNumbers == false)
        #expect(result?.options.sourceMode == true)
        #expect(result?.options.showSidebar == false)
        #expect(result?.options.sortOrder == .alphabetical)
    }

    @Test("オプションなしの userInfo を decode するとデフォルト値になる")
    func decodesMinimalUserInfo() {
        let userInfo: [AnyHashable: Any] = [
            "paths": ["/tmp/a.mmd"],
        ]

        let result = openPayload(CLIInstanceRouter.decode(userInfo: userInfo))

        #expect(result != nil)
        #expect(result?.paths == ["/tmp/a.mmd"])
        #expect(result?.options.showHiddenFiles == nil)
        #expect(result?.options.showLineNumbers == nil)
        #expect(result?.options.sourceMode == nil)
        #expect(result?.options.sortOrder == nil)
    }

    @Test("bookmarkPaths キーがあればブックマーク要求として decode される")
    func decodesBookmarkRequest() {
        let userInfo: [AnyHashable: Any] = [
            "bookmarkPaths": ["/tmp/a.mmd", "/tmp/b.md"],
            "requestID": "test-id",
        ]

        let result = CLIInstanceRouter.decode(userInfo: userInfo)

        #expect(result == .bookmark(paths: ["/tmp/a.mmd", "/tmp/b.md"]))
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
