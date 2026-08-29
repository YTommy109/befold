import BefoldKit
import Foundation

extension ViewerDisplayMode {
    /// 任意のモード（記憶値とは限らない）を、その種別で成立するモードまで降格して返す。
    ///
    /// - `.source` はレンダリング表示との切替を持つ種別でのみ成立する。コード種別は
    ///   そもそもレンダリング表示を持たず（`supportsSourceMode` が false）、常にソースを
    ///   出しているため、モードとしては `.rendered` のまま扱う
    /// - `.diff` の可否は `.source` とは別の条件（差分を描ける種別か）で決める。
    ///   コード種別は `supportsSourceMode` が false でも差分は重ねられるため、
    ///   ここを `.source` の条件に相乗りさせるとコードファイルの差分が復元されない
    ///
    /// 降格の規則はこの 1 箇所だけに置く
    /// （`WindowPresentationMemory.restoredDisplayMode` もここを通る）。
    ///
    /// ファイルを `ViewerDisplayMode.swift` 本体から分けてあるのは依存の局所化のため。
    /// `FileType` への依存（`import BefoldKit`）をこの拡張だけに閉じる。
    func supported(for url: URL) -> ViewerDisplayMode {
        let fileType = FileType(url: url)
        let sourceOrRendered: ViewerDisplayMode = fileType.supportsSourceMode ? .source : .rendered
        switch self {
        case .rendered:
            return .rendered
        case .source:
            return sourceOrRendered
        case .diff:
            guard fileType.supportsDiffDisplay else { return sourceOrRendered }
            return .diff
        }
    }
}
