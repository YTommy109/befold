import Foundation
import PDFKit

/// 読み込んだ Data を PDF として解釈する唯一の入口。
///
/// **`PDFDocument(data:)` を呼ぶのはここだけ。** 表示側(`PDFPreviewView` が
/// `PDFView` へ渡す文書)と読み込み側(拒否理由を決める)が別々の条件で「開けるか」を
/// 決めると、「読み込みは通ったのに描画面は空白」という食い違いが生まれる。
/// 両者が `PDFDocument(data:)` が nil を返すかどうかという同じ 1 つの事実を見る。
/// この約束は `.swiftlint.yml` の `pdf_document_creation_outside_probe` が
/// 機械で守っている(直呼びを書くとビルドが落ちる)。
///
/// **このターゲットは PDFKit を置くためだけに存在する。** `BefoldKit` は
/// Foundation だけで成立する層に保つ(TASK-598。`scripts/check-befoldkit-platform-free.sh`
/// が担保)ため、PDFKit を要する判定はここへ隔離し、`BefoldKit` へは
/// `@Sendable (Data) -> Bool` として注入する。
public enum PDFDataProbe {
    /// PDF として開けるか。
    ///
    /// バックグラウンドの読み込みタスクから呼ぶため nonisolated。生成した
    /// `PDFDocument` はここで捨て、**Bool しか返さない**。`PDFDocument` は
    /// Sendable ではないので、アクターをまたいで運べる形にしてはいけない。
    public static func isReadable(_ data: Data) -> Bool {
        makeDocument(data) != nil
    }

    /// 表示に使う `PDFDocument` を作る。
    ///
    /// **同一アクター内でのみ使う。** 戻り値は Sendable ではないため、アクターを
    /// またごうとするとコンパイルエラーになる(それがこの型の守り方)。表示側は
    /// MainActor 上で呼び、そのまま `PDFView` へ渡す。開けるかどうかだけが要る
    /// 背景経路は `isReadable` を使うこと。
    public static func makeDocument(_ data: Data) -> PDFDocument? {
        PDFDocument(data: data)
    }
}
