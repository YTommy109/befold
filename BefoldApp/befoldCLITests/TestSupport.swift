import Foundation

/// 一時ディレクトリを作成し、インスタンス解放時に削除する。
/// 非同期テストでディレクトリを使い終わる前に解放されないよう、
/// テスト冒頭で `defer { withExtendedLifetime(tmp) {} }` を置くこと。
///
/// befoldTests/TestSupport.swift と同型だが、befoldCLITests を befoldTests→befold(GUI 本体)→
/// BefoldRenderKit の依存グラフに引き込まないよう意図的に複製している。
final class TempDir: Sendable {
    let url: URL

    init(prefix: String = "befold-cli-test", base: URL = FileManager.default.temporaryDirectory) throws {
        url = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// ディレクトリ内にファイルを作成して URL を返す。
    func file(named name: String, contents: String) throws -> URL {
        let file = url.appendingPathComponent(name)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// 実体ファイルと、それを指す symlink を作成して両方の URL を返す。
    /// symlink 経由でも同一ファイルとして扱われることの検証に使う。
    func symlinkedFile(
        real realName: String = "real.md", link linkName: String = "link.md"
    ) throws -> (real: URL, link: URL) {
        let real = url.appendingPathComponent(realName)
        try Data().write(to: real)
        let link = url.appendingPathComponent(linkName)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        return (real, link)
    }
}

/// テストごとに独立した UserDefaults スイートを用意する。
/// 本番の CLIBookmarkDefaults 相当のスイート("com.degino.befold")への書き込みを避けるため、
/// BookmarkStore の挙動を検証するテストはこちらを介した独立領域を使う。
func makeIsolatedDefaults(prefix: String) -> UserDefaults {
    let suiteName = "\(prefix)-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
