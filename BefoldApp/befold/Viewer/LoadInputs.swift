import BefoldKit
import Foundation

/// 読み込みに要る入力の束。**アクターを離れて渡す**ので Sendable。
///
/// 3 つを個別の引数で渡すと `startLoad` の引数が 6 個になり `function_parameter_count`
/// に触れる。束ねる形にしたのは行数合わせではなく、これらが「1 回の読み込みの入力」
/// という 1 つの関心だから（生成元も `ViewerStore` の stored property 3 つで固定）。
struct LoadInputs: Sendable {
    let resolved: URL
    let fileType: FileType
    let fileReader: any FileReading
    let contentLoader: ContentLoader
    let chunkedReaderFactory: ViewerLoadPipeline.ChunkedReaderFactory
}
