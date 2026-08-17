import BefoldKit
import Foundation

/// 提示状態から `ViewerCapabilities` を組み立てる（ADR 0002 段 2 の導出そのもの）。
///
/// `ViewerCapabilities` 自身は `import Foundation` だけの純粋な値型に保ち、
/// `ViewerStore` や `URL` から Bool を取り出す作業（＝**どの入力を信じるか**）はこちらに置く。
/// 両者を 1 つのイニシャライザへ畳むと、`supportsDiffDisplay` だけ入力が違う理由が
/// 見えなくなり、揃えたくなる圧力が生まれる（TASK-338 の再発経路）。
///
/// ウィンドウを知らない純関数なので、種別ごとの導出はここを直接呼ぶユニットテストで押さえられる。
@MainActor
enum ViewerCapabilitiesFactory {
    /// `gitDiffAvailability` は**既定値を持たせない**。差分の可否は git 側の事実に
    /// 依存するようになったため、渡し忘れが静かに「常に選べる」へ倒れる形を作らない。
    ///
    /// - Parameter fileURL: 差分の種別ゲートだけが使う「いま表示中の URL」。
    ///   `store.contentState.fileType` は非同期のコンテンツロード完了まで旧ファイルの値を保つため、
    ///   切替中に届いた取得契機（`.git/index` 変更・他ウィンドウの保存）が旧ファイルの
    ///   種別で通り、差分を描けない CSV/TSV に対して git を起こしてしまう（TASK-338）。
    static func make(
        store: ViewerStore,
        isPresentingDocument: Bool,
        fileURL: URL,
        gitDiffAvailability: GitDiffAvailability,
        isDirectHTMLMode: Bool
    ) -> ViewerCapabilities {
        ViewerCapabilities(
            isPresentingDocument: isPresentingDocument,
            isRejected: store.contentState.isRejected,
            isRenderable: store.contentState.fileType.isRenderable,
            isBinaryContent: store.contentState.fileType.isBinaryContent,
            showsCodeContent: store.showsCodeContent,
            showsDiff: store.showsDiff,
            supportsSourceMode: store.contentState.fileType.supportsSourceMode,
            supportsDiffDisplay: FileType(url: fileURL).supportsDiffDisplay,
            gitDiffAvailability: gitDiffAvailability,
            isDirectHTMLMode: isDirectHTMLMode,
            // 開発中機能のゲートを読むのはここだけ。能力の導出へ畳むことで、
            // メニューの有効判定とコマンドの実行ガードの両方が自動で塞がる
            // (露出点を数え上げて回る形にしない / TASK-485.1)。
            isDocumentJumpEnabled: FeatureGate.isDocumentJumpEnabled
        )
    }
}
