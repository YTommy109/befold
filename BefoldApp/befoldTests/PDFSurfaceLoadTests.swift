@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import PDFKit
import Testing

/// PDF を `PDFView` で描くための読み込み経路(TASK-564.1)。
///
/// PDF だけが base64 を経由せず `Data` のまま運ばれる。ここでは
/// 「Data で来ること」「壊れた PDF が拒否理由になること」「表示状態へ
/// そのまま載ること」を固定する。描画そのもの(`PDFView`)は自動テストの対象外。
@Suite
struct PDFSurfaceLoadTests {
    private func makeOutcome(data: Data) async -> ViewerLoadPipeline.Outcome {
        let url = URL(fileURLWithPath: "/files/doc.pdf")
        let reader = InMemoryFileReader()
        reader.setDataFile(data, at: url)
        return await ViewerLoadPipeline.load(
            resolved: url,
            fileType: .pdf,
            fileReader: reader,
            contentLoader: ContentLoader(fileReader: reader),
            chunkedReaderFactory: ViewerLoadPipeline.defaultChunkedReaderFactory
        )
    }

    @Test("PDF は base64 の .full ではなく生データの .binary で返る")
    func pdfLoadsAsRawBinary() async {
        let data = minimalPDFData()

        let outcome = await makeOutcome(data: data)

        guard case let .binary(loaded) = outcome else {
            Issue.record(".binary を期待したが \(outcome) だった")
            return
        }
        #expect(loaded.rejectReason == nil)
        #expect(loaded.data == data)
        #expect(loaded.contentHash != nil)
    }

    @Test("PDF として開けないデータは damagedDocument で拒否される")
    func damagedPDFIsRejected() async {
        let outcome = await makeOutcome(data: Data("not a pdf".utf8))

        guard case let .binary(loaded) = outcome else {
            Issue.record(".binary を期待したが \(outcome) だった")
            return
        }
        // 読み込み自体は成功しているので、ここで理由を付けないと PDFView が
        // 黙って空白を出すだけになる(バナーも出ない)。
        #expect(loaded.rejectReason == .damagedDocument)
        #expect(loaded.data == nil)
    }

    @Test("画像は従来どおり base64 の .full 経路のまま")
    func imagesStayOnTheBase64Path() async {
        let url = URL(fileURLWithPath: "/files/img.png")
        let reader = InMemoryFileReader()
        reader.setDataFile(Data([0x89, 0x50, 0x4E, 0x47]), at: url)

        let outcome = await ViewerLoadPipeline.load(
            resolved: url,
            fileType: .image(mimeType: "image/png"),
            fileReader: reader,
            contentLoader: ContentLoader(fileReader: reader),
            chunkedReaderFactory: ViewerLoadPipeline.defaultChunkedReaderFactory
        )

        guard case .full = outcome else {
            Issue.record(".full を期待したが \(outcome) だった")
            return
        }
    }

    @Test("base64 経路とデータ経路はサイズ上限と hash の規則を共有する")
    func bothBinaryPathsShareLimitsAndHash() {
        let reader = InMemoryFileReader()
        let file = URL(fileURLWithPath: "/files/doc.pdf")
        let data = Data([0x25, 0x50, 0x44, 0x46])
        reader.setDataFile(data, at: file)
        let loader = ContentLoader(fileReader: reader)

        let asData = loader.loadData(from: file, computeHash: true)
        let asBase64 = loader.load(from: file, fileType: .pdf, computeHash: true)
        #expect(asData.data == data)
        #expect(asBase64.content == data.base64EncodedString())
        // hash はどちらも base64 化前の生データから取るので一致する。
        #expect(asData.contentHash == asBase64.contentHash)

        reader.setSize(ContentLoader.maxFileSizeBytes + 1, at: file)
        let oversized = loader.loadData(from: file, computeHash: true)
        #expect(oversized.rejectReason == .fileTooLarge)
        #expect(oversized.data == nil)
        #expect(oversized.contentHash == nil)
    }

    @MainActor
    @Test("読み込んだ PDF の Data が表示状態へそのまま載る")
    func displayStateCarriesTheData() async throws {
        let data = minimalPDFData()
        let outcome = await makeOutcome(data: data)
        let state = try #require(
            ViewerContentState.DisplayState(outcome: outcome, fileType: .pdf)
        )
        let contentState = ViewerContentState()

        #expect(contentState.applyDisplayState(state))

        #expect(contentState.fileType == .pdf)
        #expect(contentState.data == data)
        // PDF は文字列の本文を持たない(描くのは PDFView)。
        #expect(contentState.content.isEmpty)
        #expect(contentState.rejectReason == nil)
    }
}
