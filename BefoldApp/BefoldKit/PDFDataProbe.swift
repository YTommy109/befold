import Foundation
import PDFKit

/// 読み込んだ Data が PDF として開けるかどうかの判定。
///
/// **判定をここ 1 箇所に置く。** 表示側(`PDFView` へ渡す `PDFDocument`)と
/// 読み込み側(拒否理由を決める)が別々の条件で「開けるか」を決めると、
/// 「読み込みは通ったのに描画面は空白」という食い違いが生まれる。
/// `PDFDocument(data:)` が nil を返すかどうかという同じ 1 つの事実を両者が見る。
///
/// バックグラウンドの読み込みタスクから呼ぶため nonisolated。生成した
/// `PDFDocument`(Sendable 非準拠)はここで捨て、アクターをまたいで運ばない。
/// 表示側は `PDFPreviewView` が MainActor 上で作り直す。
public enum PDFDataProbe {
    /// PDF として開けるか。
    public static func isReadable(_ data: Data) -> Bool {
        PDFDocument(data: data) != nil
    }
}
