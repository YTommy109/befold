import Foundation

/// 一時ディレクトリを作成し、インスタンス解放時に削除する。
/// 非同期テストでディレクトリを使い終わる前に解放されないよう、
/// テスト冒頭で `defer { withExtendedLifetime(tmp) {} }` を置くこと。
public final class TempDir: Sendable {
    public let url: URL

    /// - Parameter base: 作成先の親ディレクトリ。省略時はシステム一時ディレクトリ。
    ///   ホーム直下には作らない(強制終了で残るため。`scripts/check-no-home-test-dirs.sh` が検査する)。
    ///   ホーム配下の判定が要るテストは、一時ディレクトリを `home:` で注入する。
    public init(
        prefix: String = "befold-test",
        base: URL = FileManager.default.temporaryDirectory
    ) throws {
        url = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// ディレクトリ内にファイルを作成して URL を返す。
    public func file(named name: String, contents: String) throws -> URL {
        let file = url.appendingPathComponent(name)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// サブディレクトリを含むパス(例: "sub/target.md")にファイルを作成して URL を返す。
    /// 中間ディレクトリが存在しない場合は自動的に作成する。
    public func file(atPath relativePath: String, contents: String) throws -> URL {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// ディレクトリ内にバイト列でファイルを作成して URL を返す。
    public func file(named name: String, data: Data) throws -> URL {
        let file = url.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }

    /// 実体ファイルと、それを指す symlink を作成して両方の URL を返す。
    /// symlink 経由でも同一ファイルとして扱われることの検証に使う。
    public func symlinkedFile(
        real realName: String = "real.mmd", link linkName: String = "link.mmd"
    ) throws -> (real: URL, link: URL) {
        let real = url.appendingPathComponent(realName)
        try Data().write(to: real)
        let link = url.appendingPathComponent(linkName)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        return (real, link)
    }

    /// 実体ディレクトリと、それを指す symlink を作成して両方の URL を返す。
    /// symlink 経由のディレクトリでも同一とみなされることの検証に使う。
    public func symlinkedDirectory(
        real realName: String = "real", link linkName: String = "link"
    ) throws -> (real: URL, link: URL) {
        let real = url.appendingPathComponent(realName)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = url.appendingPathComponent(linkName)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        return (real, link)
    }
}
