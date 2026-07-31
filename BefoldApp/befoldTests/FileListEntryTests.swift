@testable import befold
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

    @Test("pathKey は構築時に url.normalizedPathKey を保持する")
    func pathKeyMatchesNormalizedPathKey() {
        let url = URL(fileURLWithPath: "/tmp/diagram.mmd")
        #expect(FileListEntry(url: url, kind: .file).pathKey == url.normalizedPathKey)
    }
}
