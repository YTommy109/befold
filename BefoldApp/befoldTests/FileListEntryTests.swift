@testable import befold
import BefoldTestSupport
import Foundation
import Testing

@Suite
struct FileListEntryTests {
    @Test("hasUnknownExtension は未知拡張子のファイルのみ true", arguments: [
        (URL(fileURLWithPath: "/tmp/diagram.mmd"), FileListEntry.Kind.file, false),
        (URL(fileURLWithPath: "/tmp/unknown.xyz"), .file, true),
        (URL(fileURLWithPath: "/tmp/subdir"), .folder, false),
    ])
    func hasUnknownExtension(url: URL, kind: FileListEntry.Kind, expected: Bool) {
        #expect(FileListEntry(url: url, kind: kind).hasUnknownExtension == expected)
    }

    /// `FileListEntryRow.nameLabel` はフォルダー行とファイル行で同じ式を使い、
    /// フォルダーが `.primary` になることをこの述語に委ねている。ここが true を
    /// 返すようになるとフォルダー名が淡色で描かれる(issue #509 の逆向きの回帰)。
    @Test("未知拡張子に見える名前のフォルダーでも hasUnknownExtension は false")
    func folderWithUnknownLookingNameIsNotDimmed() {
        let url = URL(fileURLWithPath: "/tmp/archive.xyz")

        #expect(FileListEntry(url: url, kind: .folder).hasUnknownExtension == false)
        #expect(FileListEntry(url: url, kind: .file).hasUnknownExtension)
    }

    @Test("pathKey は構築時に url.normalizedPathKey を保持する")
    func pathKeyMatchesNormalizedPathKey() {
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")
        #expect(FileListEntry(url: url, kind: .file).pathKey == url.normalizedPathKey)
    }

    @Test("FileManager 由来の URL でも url は native 裏打ちに揃い、元の URL と等しい")
    func urlIsNativeBackedEvenFromFileManager() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileListEntryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent("日本語ファイル.md"))

        let listed = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let source = try #require(listed.first { $0.pathExtension == "md" })

        // FileManager 由来の URL は NSString 裏打ちで Hashable が遅い正規化経路を通る。
        // id・pathKey ともに native 裏打ちへ揃っていること（値は元の URL と同じまま）を見る。
        // 裏打ちが揃うかは OS の実装によるため、この環境で実測した結果と一致するかで判定する。
        // アサートを飛ばさずに突き合わせることで、「揃う環境なのに揃っていない」だけでなく
        // 「揃わない環境なのに揃った」も捕まえる。id と pathKey は別の API を通るので、
        // それぞれ対応する観測値と比べる。
        let backing = try URLBackingSupport.observed()
        let entry = FileListEntry(url: source, kind: .file)
        #expect(entry.url.path.isContiguousUTF8 == backing.rebuiltPathIsContiguousUTF8)
        #expect(entry.pathKey.isContiguousUTF8 == backing.resolvedPathIsContiguousUTF8)
        #expect(entry.url == source)
        #expect(entry.pathKey == source.normalizedPathKey)
    }
}
