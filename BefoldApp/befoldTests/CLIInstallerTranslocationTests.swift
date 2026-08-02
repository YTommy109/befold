@testable import BefoldCLI
import BefoldTestSupport
import Foundation
import Testing

/// App Translocation 下のバンドルからのインストールを拒否できることを検証する。
/// 判定はパス文字列のみに依存する純粋関数のため unit。
@Suite
struct CLIInstallerTranslocationTests {
    /// quarantine 付きで Downloads 等から起動されたアプリは、ランダム化された読み取り専用
    /// マウント配下で実行される。このパスは次回起動や再起動で消えるため、symlink 先にできない。
    @Test("AppTranslocation マウント配下のバンドルパスを translocated と判定する")
    func detectsTranslocatedBundlePath() {
        let translocated =
            "/private/var/folders/7x/2m9d0000gn/T/AppTranslocation/"
                + "A1B2C3D4-0000-1111-2222-333344445555/d/befold.app"

        #expect(CLIInstaller.isTranslocated(bundlePath: translocated))
    }

    @Test(
        "通常の設置場所は translocated と判定しない",
        arguments: [
            "/Applications/befold.app",
            "/Users/me/Applications/befold.app",
            "/Users/me/Downloads/befold.app",
            "/Volumes/befold/befold.app",
            // 名前に AppTranslocation を含むだけのパスは対象外(マウント配下ではない)。
            "/Users/me/AppTranslocationNotes/befold.app",
        ]
    )
    func doesNotFlagNormalBundlePaths(path: String) {
        #expect(!CLIInstaller.isTranslocated(bundlePath: path))
    }

    /// 検出できても symlink を作ってしまえば意味がない。install が実際に書き込みを行わず
    /// 専用のエラーを返すことを、書き込み可能な installPath を渡した状態で確かめる。
    @Test("translocated なバンドルからの install は書き込まずに専用エラーを返す")
    func installRefusesTranslocatedBundleWithoutWriting() throws {
        let tmp = try TempDir(prefix: "CLIInstallerTranslocationTests")
        defer { withExtendedLifetime(tmp) {} }
        let installPath = tmp.url.appendingPathComponent("befold")
        let translocated =
            "/private/var/folders/7x/2m9d0000gn/T/AppTranslocation/"
                + "A1B2C3D4-0000-1111-2222-333344445555/d/befold.app"

        let result = CLIInstaller.install(bundlePath: translocated, installPath: installPath)

        guard case let .failure(error) = result else {
            Issue.record("install が成功してしまった")
            return
        }
        #expect(error == .translocatedBundle)
        #expect(!FileManager.default.fileExists(atPath: installPath.path))
    }
}
