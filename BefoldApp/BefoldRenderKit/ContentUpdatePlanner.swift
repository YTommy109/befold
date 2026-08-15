import BefoldKit
import Foundation

/// updateContent が受け取った 1 回分の入力。
struct ContentUpdateInput {
    let content: String
    let contentRevision: Int
    let fileType: FileType
    let filePath: URL?
    let hasDeclaredHTMLCharset: Bool?
    let isSourceMode: Bool
    let showLineNumbers: Bool
    let truncation: TruncationState
    /// 呼び出し時点の contentUpdateGeneration のスナップショット。
    let generation: Int
    /// ソース表示へ重ねる git 差分。再描画要否の判定に含める。
    let diffState: DiffState
}

/// updateContent が取るべき行動。
enum UpdatePlan: Equatable {
    /// HTML を viewer.html を介さず直接ロードする。
    case directHTMLLoad(filePath: URL)
    /// 直接 HTML モードを抜けてから全文 render する。
    case exitDirectThenRender(RenderRequest, restoreFromPersistedPosition: Bool)
    /// 段階読み込みの続きを増分追記する。
    case append(AppendRequest)
    /// 全文 render する。
    case render(RenderRequest, restoreFromPersistedPosition: Bool)
    /// 描画済みと差が無いので何もしない。
    case skip
}

/// updateContent の意思決定を、状態遷移を伴わない純粋な計算として切り出したもの。
///
/// 分岐が副作用と混ざっていると、判定の網羅性をテストで押さえるのに WKWebView の実体が
/// 要る。ここを純関数にすることで、全分岐をユニットテストで確認できる。
enum ContentUpdatePlanner {
    nonisolated static func plan(
        input: ContentUpdateInput,
        rendered: RenderedStateMirror,
        pendingAppend: PendingAppend?,
        isDirectHTMLActive: Bool,
        features: RendererFeatures
    ) -> UpdatePlan {
        // content・fileType だけでなく isSourceMode の変化でも再描画する。
        // (例: notes.md → notes.txt のように内容が同じでも種別が変わる切替、
        // ソース/レンダリング表示の切替も同じ content から異なる文字列を描画し直す必要がある。
        // 差分の到着・レイアウト変更も同様に別の DOM を作り直す)
        //
        // 個々のフィールドを並べて比較せず、描画済みミラーと同じ形の値を組んで
        // 丸ごと比較する。列挙にすると、ミラーへフィールドを足したときに
        // ここへの追加だけ漏れて「状態は変わったのに再描画されない」形の穴が空く。
        // 下の pendingAppend 消費可否も同じ値を使って判定する(判定が 2 箇所あるので、
        // 片方だけ列挙式で残すと同じ穴がそちらに空く)。
        let incoming = RenderedStateMirror(
            contentRevision: input.contentRevision, fileType: input.fileType, filePath: input.filePath,
            showLineNumbers: input.showLineNumbers, isSourceMode: input.isSourceMode,
            truncation: input.truncation, diffState: input.diffState
        )

        // 差分が未確定(pending)の間、モード切替だけの入力なら再描画を見送って前の表示を
        // 残す(差分なしのプレーンなソース表示が中間状態として一瞬見えるのを防ぐ = TASK-407)。
        // コンテンツ自体が変わる入力(初回描画・ファイル切替・保存や追記読み込み)は従来どおり
        // 描画へ進める(見送ると空白画面や旧ファイルの残留になる)。direct HTML 分岐より前に
        // 置くのは、HTML の .rendered(直接ロード)からの切替が exitDirectThenRender を通って
        // 同じ中間描画を起こすため。pending はソース系モードでしか生成されず、directHTMLLoad
        // (shouldEnter)は isSourceMode=false が条件なので、この見送りが直接ロードを奪うことはない。
        if input.diffState.isPending, holdsPreviousFrame(incoming: incoming, rendered: rendered) {
            return .skip
        }

        // HTML レンダリング表示: loadFileURL で直接ロード
        if DirectHTMLModeController.shouldEnter(
            fileType: input.fileType, isSourceMode: input.isSourceMode,
            filePath: input.filePath, features: features
        ), let filePath = input.filePath {
            return .directHTMLLoad(filePath: filePath)
        }

        // 直接 HTML モードから viewer.html モードへの復帰。
        // この分岐に来る時点でファイルかモードが直接 HTML 状態と必ず異なるため
        // (同一なら上の直接 HTML ロード分岐に吸収される)、常に切替として扱われる。
        if isDirectHTMLActive {
            return .exitDirectThenRender(
                renderRequest(input), restoreFromPersistedPosition: isSwitch(input, rendered: rendered)
            )
        }

        // 段階読み込みの続き(loadMoreLines)は handleLoadMoreLines が pendingAppend として
        // ステージする。追記で正しく更新できる差(内容の世代と切り詰め状態)しか無ければ
        // 全文 render せず増分追記する。これで「追記の描画」経路が updateContent 1 本に集約される。
        // 条件不一致(別の読み込みに追い越された・同一サイクルで行番号や差分の切替も
        // 起きた等)の場合は破棄し、下の通常経路で全文 render に倒す。
        let isConsumable = pendingAppend.map {
            RenderedStateMirror.canConsume($0, incoming: incoming, rendered: rendered)
        } ?? false
        if let pending = pendingAppend, isConsumable {
            return .append(
                AppendRequest(
                    chunk: pending.chunk, contentRevision: input.contentRevision,
                    fileType: input.fileType, filePath: input.filePath,
                    isSourceMode: input.isSourceMode, truncation: input.truncation,
                    generation: input.generation
                )
            )
        }

        guard incoming != rendered else { return .skip }
        return .render(renderRequest(input), restoreFromPersistedPosition: isSwitch(input, rendered: rendered))
    }

    private nonisolated static func renderRequest(_ input: ContentUpdateInput) -> RenderRequest {
        RenderRequest(
            content: input.content, contentRevision: input.contentRevision, fileType: input.fileType,
            filePath: input.filePath, isSourceMode: input.isSourceMode,
            showLineNumbers: input.showLineNumbers, truncation: input.truncation,
            generation: input.generation
        )
    }

    /// 差分が未確定(pending)の間、前の表示を残してよいか。
    /// isSourceMode / diffState 以外のフィールドが描画済みと一致するときだけ true。
    /// フィールドを列挙して比較せず、その 2 つを描画済み側の値へ揃えた上で丸ごと
    /// 比較する(ミラーへフィールドを足したときにここだけ漏れる穴を防ぐ。canConsume と同型)。
    /// 未描画(空のミラー)は contentRevision の不一致で自然に false になり、描画へ進む。
    private nonisolated static func holdsPreviousFrame(
        incoming: RenderedStateMirror, rendered: RenderedStateMirror
    ) -> Bool {
        var comparable = incoming
        comparable.isSourceMode = rendered.isSourceMode
        comparable.diffState = rendered.diffState
        return comparable == rendered
    }

    private nonisolated static func isSwitch(
        _ input: ContentUpdateInput, rendered: RenderedStateMirror
    ) -> Bool {
        RenderedStateMirror.isFileOrModeSwitch(
            filePath: input.filePath, isSourceMode: input.isSourceMode,
            lastRenderedFilePath: rendered.filePath, lastIsSourceMode: rendered.isSourceMode
        )
    }
}
