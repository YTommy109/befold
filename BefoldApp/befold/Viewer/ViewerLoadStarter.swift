import BefoldKit
import Foundation

/// 読み込みの**開始**だけを持つ。`ViewerStore` の状態に触らないので型を分けてある
/// （`ViewerStore` グループの行数からも外れる）。
enum ViewerLoadStarter {
    /// 読み込みを開始する。**`nonisolated` なのが要点**で、ここで作る `Task` は
    /// アクターを継承せず、協調プールで**即座に**走り出す。
    ///
    /// `@MainActor` の文脈で `Task {}` を作ると MainActor を継承するため、切り替えで
    /// 積まれた他の仕事（サイドバー同期・ツールバー更新・SwiftUI 再評価）が捌けるまで
    /// **読み込みが開始すらしない**。実測（2026-09-01・切り替え時）ではこの待ちが
    /// 13〜21ms で、読み込みの実処理（1〜4ms）の 4〜15 倍だった。起動直後や
    /// セッション復元のように MainActor が混んでいる場面では 446ms まで伸びる。
    ///
    /// **ここへ `@MainActor` を付けたり、呼び出しを `loadContent` の中へ戻したりしないこと。**
    /// どちらも待ちが復活する。`ViewerStoreLoadStartTests` が、MainActor を塞いだ状態でも
    /// 読み込みが進むことを見て固定している。
    ///
    /// `Task.detached` は使わない（このリポジトリでは pre-commit が禁止している）。
    /// 捕捉する 3 つはいずれも Sendable（`FileReading` / `ContentLoader` / `@Sendable`
    /// クロージャ）なので、アクターを離れて渡せる。
    ///
    /// - Parameter apply: 読み込み結果を表示へ渡す処理。MainActor 上で 1 回だけ呼ばれる。
    nonisolated static func start(
        _ inputs: LoadInputs,
        apply: @escaping @MainActor (ViewerLoadPipeline.Outcome) -> Void
    ) -> Task<Void, Never> {
        Task {
            let outcome = await ViewerLoadPipeline.load(
                resolved: inputs.resolved,
                fileType: inputs.fileType,
                fileReader: inputs.fileReader,
                contentLoader: inputs.contentLoader,
                chunkedReaderFactory: inputs.chunkedReaderFactory
            )
            // キャンセルの確認は MainActor へ戻る前に行う。戻ってから見ると、
            // 閉じた窓の状態へ触りに行くぶんだけ無駄が増える。
            guard !Task.isCancelled else { return }
            await apply(outcome)
        }
    }
}
