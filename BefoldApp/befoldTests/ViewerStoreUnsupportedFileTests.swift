@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// バイナリ/サイズ超過などの非対応ファイルを開いたときの reject 判定と、その解除・境界を検証する。
@Suite
@MainActor
struct ViewerStoreUnsupportedFileTests {
    /// 非対応ファイルの1ケース。`configure` がバイナリ/サイズ超過などの非対応条件を注入する。
    private struct UnsupportedFileCase: Sendable, CustomTestStringConvertible {
        let name: String
        let filename: String
        let content: String
        let configure: @Sendable (InMemoryFileReader, URL) -> Void
        let expectedReason: RejectReason
        var testDescription: String {
            name
        }
    }

    private nonisolated static let unsupportedFileCases: [UnsupportedFileCase] = [
        UnsupportedFileCase(
            name: "バイナリファイル", filename: "data.bin", content: "binary-ish",
            configure: { reader, url in reader.setBinary(true, at: url) },
            expectedReason: .binaryContent
        ),
        UnsupportedFileCase(
            name: "サイズ超過ファイル", filename: "huge.html", content: "<h1>Hello</h1>",
            configure: { reader, url in reader.setSize(ContentLoader.maxTextFileSizeBytes + 1, at: url) },
            expectedReason: .fileTooLarge
        ),
    ]

    @Test("非対応ファイルを開くと reject 理由が設定されコンテンツは読み込まれない", arguments: unsupportedFileCases)
    private func openUnsupportedFileMarksUnsupported(_ testCase: UnsupportedFileCase) async {
        let file = URL(fileURLWithPath: "/files/\(testCase.filename)")
        let reader = InMemoryFileReader()
        reader.setFile(testCase.content, at: file)
        testCase.configure(reader, file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(store.contentState.rejectReason == testCase.expectedReason)
        #expect(store.contentState.content == "")

        store.close()
    }

    @Test
    func openTextFileWithUnknownExtensionIsNotUnsupported() async {
        let file = URL(fileURLWithPath: "/files/notes.txt")
        let reader = InMemoryFileReader()
        reader.setFile("hello", at: file)

        let store = makeStore(
            reader: reader,
            chunkedReaderFactory: { _, _ in MockChunkedReader(chunks: ["hello"]) }
        )
        await openAndLoad(store, file)

        #expect(!store.contentState.isRejected)
        #expect(store.contentState.content == "hello")
        #expect(store.contentState.fileType == .code(language: "plaintext"))

        store.close()
    }

    @Test
    func openFileAtSizeLimitLoadsContent() async {
        let file = URL(fileURLWithPath: "/files/ok.md")
        let reader = InMemoryFileReader()
        reader.setFile("# Hello", at: file)
        reader.setSize(ContentLoader.maxTextFileSizeBytes, at: file)

        let store = makeStore(reader: reader)
        await openAndLoad(store, file)

        #expect(!store.contentState.isRejected)
        #expect(store.contentState.content == "# Hello")

        store.close()
    }

    @Test("非対応ファイルから通常ファイルへ切り替えると unsupported 状態が解除される", arguments: unsupportedFileCases)
    private func switchingFromUnsupportedToNormalResetsUnsupported(_ testCase: UnsupportedFileCase) async {
        let rejectedFile = URL(fileURLWithPath: "/files/\(testCase.filename)")
        let normalFile = URL(fileURLWithPath: "/files/readme.md")
        let reader = InMemoryFileReader()
        reader.setFile(testCase.content, at: rejectedFile)
        testCase.configure(reader, rejectedFile)
        reader.setFile("# Hello", at: normalFile)

        let store = makeStore(reader: reader)
        await openAndLoad(store, rejectedFile)
        #expect(store.contentState.isRejected)

        await openAndLoad(store, normalFile)
        #expect(!store.contentState.isRejected)
        #expect(store.contentState.content == "# Hello")

        store.close()
    }
}
