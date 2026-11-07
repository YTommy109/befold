import Foundation
import Testing

/// 「PDFView を作るテストは名前に PDF を含む」という規則を固定する(TASK-907)。
///
/// CI は `swift test --filter PDF` で PDF のテストを別プロセスに分ける。PDFView の Vision
/// 解析が、キャッシュの無い環境で libdispatch のワーカーを使い切り、同じプロセスの実
/// WKWebView のロードを止めるため(実測: 一緒に回すと 5/6 でハング、分けると 0/6)。
/// 名前に PDF を含まないスイートが PDFView を作ると分離から漏れ、稀なハングとして
/// 戻ってくる。CI の 1 回の実行では気づけないので、ここで落とす。
@Suite
struct PDFTestIsolationGuardTests {
    private static let testsRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    /// PDFView を生成する式。テストが表示まで進める経路はこのいずれかを通る。
    private static let creators = ["ZoomingPDFView(", "PDFDocumentRenderer(", "PDFPreviewView(", " PDFView("]

    /// 行コメントを除いた本文に `creators` のどれかを含むか。
    static func createsPDFView(_ source: String) -> Bool {
        source.split(separator: "\n").contains { line in
            let code = line.drop { $0 == " " }
            return !code.hasPrefix("//") && creators.contains { code.contains($0) }
        }
    }

    @Test("PDFView を作るテストのファイル名は PDF を含み、--filter PDF の対象になる")
    func everyTestCreatingPDFViewIsInThePDFProcess() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.testsRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let creating = try files.filter { try Self.createsPDFView(String(contentsOf: $0, encoding: .utf8)) }

        // 探索そのものが壊れて何も見つからない状態を、合格と取り違えない。
        #expect(!creating.isEmpty)
        let leaked = creating.map(\.lastPathComponent).filter { !$0.contains("PDF") }
        #expect(leaked.isEmpty, "PDF を含まないスイートが PDFView を作っている: \(leaked)")
    }

    @Test("判定はコメントを除いて生成の式だけを見る")
    func detectionIgnoresCommentsAndOtherTypes() {
        #expect(Self.createsPDFView("let view = ZoomingPDFView(frame: .zero)"))
        #expect(Self.createsPDFView("    let view = PDFView(frame: .zero)"))
        #expect(!Self.createsPDFView("// ZoomingPDFView(frame: .zero) を作らない"))
        #expect(!Self.createsPDFView("let document = PDFDocument(data: data)"))
    }
}
