import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// `URL.nativeBackedFileURL` は「ハッシュを速くするために文字列の裏打ちだけを差し替え、
/// パスのバイト列は 1 バイトも変えない」ことが要件。バイト列が変わると、正規化に
/// 敏感なボリューム（SMB/NFS/exFAT）上のファイルを開けなくなる。
@Suite
struct URLNativeBackedFileURLTests {
    /// 精密合成（NFC）のファイル名をディスク上のバイト列そのままで作る。
    /// `Data().write(to:)` や `appendingPathComponent` は正規化を通してしまうため、
    /// 生の `open(2)` にバイト列を渡す。
    private func makeFile(named name: String, in directory: URL) throws {
        let path = directory.path + "/" + name
        let descriptor = path.withCString { open($0, O_CREAT | O_WRONLY, 0o644) }
        try #require(descriptor >= 0)
        close(descriptor)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeBackedFileURLTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("NFC のファイル名でもバイト列を変えず、元の URL と等値・同ハッシュになる", arguments: [
        "ペ-nfc.md", // U+30DA（NFD だと U+30D8 U+309A になる）
        "café-nfc.md", // U+00E9（NFD だと U+0065 U+0301 になる）
    ])
    func preservesPrecomposedFileNameBytes(name: String) throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try makeFile(named: name, in: directory)

        let listed = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        // .DS_Store 等が混ざっても作ったファイルを取り違えないよう、名前で特定する
        let source = try #require(listed.first { $0.lastPathComponent.hasSuffix("-nfc.md") })

        let rebuilt = source.nativeBackedFileURL
        #expect(rebuilt == source)
        #expect(rebuilt.hashValue == source.hashValue)
        #expect(Array(rebuilt.lastPathComponent.unicodeScalars) == Array(source.lastPathComponent.unicodeScalars))
        // 裏打ちが揃うかは OS の実装によるので、実測した結果と一致することを見る
        // (揃わない環境でアサートを飛ばすと、揃うべき環境での回帰まで黙って通る)。
        let backing = try URLBackingSupport.observed()
        #expect(rebuilt.path.isContiguousUTF8 == backing.rebuiltPathIsContiguousUTF8)
    }

    @Test("ディレクトリの URL でも末尾の区切りの意味が保たれ、元の URL と等値になる")
    func preservesDirectorySemantics() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let child = directory.appendingPathComponent("日本語フォルダー")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let listed = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let source = try #require(listed.first)

        let rebuilt = source.nativeBackedFileURL
        #expect(rebuilt == source)
        #expect(rebuilt.hasDirectoryPath == source.hasDirectoryPath)
        let backing = try URLBackingSupport.observed()
        #expect(rebuilt.path.isContiguousUTF8 == backing.rebuiltPathIsContiguousUTF8)
    }

    @Test("file URL でなければ何も書き換えずに自身を返す")
    func leavesNonFileURLUntouched() throws {
        let source = try #require(URL(string: "https://example.com/a/b?q=1#frag"))
        #expect(source.nativeBackedFileURL == source)
    }
}
