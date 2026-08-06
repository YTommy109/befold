import BefoldKit
import WebKit

// MARK: - Content update

extension ViewerRenderer {
    /// applyRender の引数をまとめた入力(function_parameter_count 対策)。
    /// generation は呼び出し時点の contentUpdateGeneration のスナップショット。画像埋め込み
    /// (MainActor 外)から戻った際にこの値と現在値を比較し、後続の updateContent 呼び出しに
    /// 追い越されていないかを確認する。
    struct RenderRequest {
        let content: String
        let contentRevision: Int
        let fileType: FileType
        let filePath: URL?
        let isSourceMode: Bool
        let showLineNumbers: Bool
        let truncation: TruncationState
        let generation: Int
    }

    /// applyAppend の引数をまとめた入力(function_parameter_count 対策)。RenderRequest 参照。
    struct AppendRequest {
        let chunk: String
        let contentRevision: Int
        let fileType: FileType
        let filePath: URL?
        let isSourceMode: Bool
        let truncation: TruncationState
        let generation: Int
    }

    /// applyRender を非同期 Task で起動する(doUpdate 内の重複削減)。
    private func scheduleRender(webView: WKWebView, request: RenderRequest, restoreFromPersistedPosition: Bool) {
        Task { @MainActor in
            await self.applyRender(
                webView: webView, request: request,
                restoreFromPersistedPosition: restoreFromPersistedPosition
            )
        }
    }

    /// applyAppend を非同期 Task で起動する(doUpdate 内の重複削減)。
    private func scheduleAppend(webView: WKWebView, request: AppendRequest) {
        Task { @MainActor in
            await self.applyAppend(webView: webView, request: request)
        }
    }
}

public extension ViewerRenderer {
    /// ソース表示へ重ねる git 差分の状態。本文とレイアウトは必ず一緒に動くため
    /// 1 つの値として持つ(片方だけ送られて、旧レイアウトで新しい差分が描かれるのを防ぐ)。
    struct DiffState: Equatable, Sendable {
        public let text: String?
        public let layout: ViewerBridge.DiffLayout
        public init(text: String?, layout: ViewerBridge.DiffLayout) {
            self.text = text
            self.layout = layout
        }

        /// 差分を出さない状態。
        public static let none = DiffState(text: nil, layout: .inline)
    }

    /// _mmdSetTruncated へ送る切り詰め状態と表示行数のペア。非切り詰め時の
    /// 行数は 0 に正規化する(切り詰め有無だけが意味を持つ)。failed はチャンク
    /// 読込エラーによる打ち切りを示す(通常の再描画経路からは常に false)。
    struct TruncationState: Equatable, Sendable {
        public let isTruncated: Bool
        public let lineCount: Int
        public let failed: Bool
        public init(isTruncated: Bool, lineCount: Int, failed: Bool) {
            self.isTruncated = isTruncated
            self.lineCount = isTruncated ? lineCount : 0
            self.failed = failed
        }

        /// この状態を JS へ反映するスクリプト。3 つのフィールドを呼び出し側で
        /// 手ばらしすると、フィールドが増えたときに渡し漏れる。
        public var script: String {
            ViewerBridge.truncatedScript(isTruncated, lineCount: lineCount, failed: failed)
        }
    }

    /// type_body_length 対策で ViewerRenderer 本体の外の extension に分離している。
    func updateContent(
        _ content: String,
        contentRevision: Int,
        fileType: FileType,
        filePath: URL?,
        hasDeclaredHTMLCharset: Bool?,
        isSourceMode: Bool,
        showLineNumbers: Bool,
        truncation: TruncationState
    ) {
        // 見えていない間は描画しない。描画済みミラー(rendered)も更新しないので、
        // 見える状態へ戻ってホストが呼び直したときに、最新の内容で 1 度だけ描画される。
        guard isVisible else { return }

        // この呼び出し固有の世代番号。applyRender/applyAppend は画像埋め込み(MainActor 外)から
        // 戻った際にこの値を渡し、後続の updateContent 呼び出しに追い越されていないかを確認する。
        contentUpdateGeneration += 1
        let generation = contentUpdateGeneration

        let doUpdate = { [weak self] in
            guard let self, let webView else { return }

            // HTML レンダリング表示: loadFileURL で直接ロード
            if Self.shouldEnterDirectHTMLMode(
                fileType: fileType, isSourceMode: isSourceMode,
                filePath: filePath, features: rendererFeatures
            ), let filePath {
                let pathChanged = filePath != lastDirectHTMLPath
                let contentChanged = contentRevision != rendered.contentRevision
                guard !isDirectHTMLMode || pathChanged || contentChanged else { return }
                // 初回ロード・ファイル切替では保存済みの per-file 倍率を使い、
                // ライブリロード（同一ファイルの content 変更）では現在の倍率を維持する。
                let isFirstLoadOrSwitch = !isDirectHTMLMode || pathChanged
                pendingPageZoom = isFirstLoadOrSwitch ? initialPageZoom : webView.pageZoom
                // 直接ロードでは viewer.js が居らず行番号・切り詰め・差分は適用されないため、
                // それらは現在のミラー値のまま持ち越す(復帰時に exitDirectHTMLMode が
                // rendered.reset() で一括破棄する)。フィールドを並べず現在値から組み立てて
                // 丸ごと確定させるのは、ミラーへフィールドを足したときの確定漏れを防ぐため。
                var state = rendered
                state.contentRevision = contentRevision
                state.fileType = fileType
                state.filePath = filePath
                state.isSourceMode = isSourceMode
                recordRendered(state)
                lastDirectHTMLPath = filePath
                isDirectHTMLMode = true
                webViewProxy?.isDirectHTMLMode = true
                isReady = false
                // 直接ロードへ入ると viewer.js が居なくなる。復帰時に再適用させる。
                appliedPageZoom = nil
                // 直接ロードする HTML 内の <script> 実行を無効化する（設計スコープ外）。
                webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = false
                // charset 宣言(BOM/<meta charset>)のある HTML は WebKit の解釈で正しく読めるため、
                // 相対リソースを読める loadFileURL のまま。宣言の無い HTML だけは WebKit が既定
                // エンコーディングを誤推定して文字化けするので、ViewerLoadPipeline が MainActor 外で
                // 判定・UTF-8 正規化済みの content を明示エンコーディングでロードする。loadData は
                // allowingReadAccessTo を伴わず宣言なし HTML から相対参照した兄弟リソースは読めなく
                // なるが、宣言なし HTML は簡易な断片が大半で影響は小さい。判定不能(nil)時は
                // loadFileURL へフォールバックする。
                if hasDeclaredHTMLCharset == false {
                    webView.load(
                        Data(content.utf8), mimeType: "text/html",
                        characterEncodingName: "UTF-8", baseURL: filePath
                    )
                } else {
                    webView.loadFileURL(filePath, allowingReadAccessTo: filePath.deletingLastPathComponent())
                }
                return
            }

            // 直接 HTML モードから viewer.html モードへの復帰
            if isDirectHTMLMode {
                // この分岐に来る時点でファイルかモードが直接HTML状態と必ず異なるため
                // (同一なら上の直接HTMLロード分岐に吸収される)、常に切替として扱われる。
                let restoreFromPersistedPosition = Self.isFileOrModeSwitch(
                    filePath: filePath, isSourceMode: isSourceMode,
                    lastRenderedFilePath: rendered.filePath, lastIsSourceMode: rendered.isSourceMode
                )
                let request = RenderRequest(
                    content: content, contentRevision: contentRevision, fileType: fileType,
                    filePath: filePath, isSourceMode: isSourceMode, showLineNumbers: showLineNumbers,
                    truncation: truncation, generation: generation
                )
                exitDirectHTMLMode(webView: webView) {
                    self.scheduleRender(
                        webView: webView, request: request,
                        restoreFromPersistedPosition: restoreFromPersistedPosition
                    )
                }
                return
            }

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
                contentRevision: contentRevision, fileType: fileType, filePath: filePath,
                showLineNumbers: showLineNumbers, isSourceMode: isSourceMode,
                truncation: truncation, diffState: diffState
            )

            // 段階読み込みの続き(loadMoreLines)は handleLoadMoreLines が pendingAppend として
            // ステージする。追記で正しく更新できる差(内容の世代と切り詰め状態)しか無ければ
            // 全文 render せず増分追記する。これで「追記の描画」経路が updateContent 1 本に集約される。
            // 条件不一致(別の読み込みに追い越された・同一サイクルで行番号や差分の切替も
            // 起きた等)の場合は破棄し、下の通常経路で全文 render に倒す。
            if let pending = pendingAppend {
                pendingAppend = nil
                if Self.canConsumePendingAppend(pending, incoming: incoming, rendered: rendered) {
                    scheduleAppend(
                        webView: webView,
                        request: AppendRequest(
                            chunk: pending.chunk, contentRevision: contentRevision,
                            fileType: fileType, filePath: filePath, isSourceMode: isSourceMode,
                            truncation: truncation, generation: generation
                        )
                    )
                    return
                }
            }

            guard incoming != rendered else { return }

            let restoreFromPersistedPosition = Self.isFileOrModeSwitch(
                filePath: filePath, isSourceMode: isSourceMode,
                lastRenderedFilePath: rendered.filePath, lastIsSourceMode: rendered.isSourceMode
            )
            scheduleRender(
                webView: webView,
                request: RenderRequest(
                    content: content, contentRevision: contentRevision, fileType: fileType,
                    filePath: filePath, isSourceMode: isSourceMode, showLineNumbers: showLineNumbers,
                    truncation: truncation, generation: generation
                ),
                restoreFromPersistedPosition: restoreFromPersistedPosition
            )
        }

        if isReady {
            doUpdate()
        } else {
            pendingUpdate = doUpdate
        }
    }
}
