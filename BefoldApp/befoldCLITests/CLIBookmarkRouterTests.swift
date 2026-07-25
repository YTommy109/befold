import AppKit
@testable import befold_cli
@testable import BefoldCLI
import Foundation
import Testing

/// ブックマークの書き込みプロセスを 1 つに保つ振り分けを検証する。
/// UserDefaults のブックマーク配列は read-modify-write で更新されるため、CLI と GUI が
/// 同時に書くと片方の追加が消える。「起動中インスタンスがあれば書くのは GUI だけ」
/// 「無ければ書くのは CLI だけ」を、どの経路でも writer が 1 つになる形で規定する。
@Suite
@MainActor
struct CLIBookmarkRouterTests {
    private let url = URL(fileURLWithPath: "/tmp/diagram.mmd")

    @Test("起動中インスタンスがあれば GUI へ転送し、CLI からは書き込まない")
    func forwardsToRunningInstanceWithoutWritingLocally() {
        var forwardedPaths: [String] = []
        var localWrites: [URL] = []

        let added = CLIBookmarkRouter.add(
            url,
            addLocally: { localWrites.append($0) },
            findRunningInstance: { NSRunningApplication.current },
            forward: { paths in
                forwardedPaths = paths
                return true
            }
        )

        #expect(added)
        #expect(forwardedPaths == [url.path])
        #expect(localWrites.isEmpty)
    }

    /// 転送不達でローカル書き込みへフォールバックすると、遅れて届いた要求を GUI が処理した際に
    /// 二重書き込みとなり、この経路で防いでいる競合が復活する。失敗はそのまま失敗として返す。
    @Test("転送に失敗してもローカル書き込みへフォールバックせず失敗を返す")
    func doesNotFallBackToLocalWriteOnForwardFailure() {
        var localWrites: [URL] = []

        let added = CLIBookmarkRouter.add(
            url,
            addLocally: { localWrites.append($0) },
            findRunningInstance: { NSRunningApplication.current },
            forward: { _ in false }
        )

        #expect(!added)
        #expect(localWrites.isEmpty)
    }

    @Test("起動中インスタンスが無ければ CLI が直接書き込む")
    func writesLocallyWhenNoRunningInstance() {
        var localWrites: [URL] = []

        let added = CLIBookmarkRouter.add(
            url,
            addLocally: { localWrites.append($0) },
            findRunningInstance: { nil },
            forward: { _ in
                Issue.record("forward should not be called without a running instance")
                return false
            }
        )

        #expect(added)
        #expect(localWrites == [url])
    }
}
