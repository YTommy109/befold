import BefoldKit
import WebKit

// MARK: - Content update

public extension ViewerRenderer {
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
    }

    /// type_body_length 対策で ViewerRenderer 本体の外の extension に分離している。
    func updateContent(
        _ content: String,
        contentRevision: Int,
        fileType: FileType,
        filePath: URL?,
        isSourceMode: Bool,
        showLineNumbers: Bool,
        truncation: TruncationState
    ) {
        let doUpdate = { [weak self] in
            guard let self, let webView else { return }

            // HTML レンダリング表示: loadFileURL で直接ロード
            if Self.shouldEnterDirectHTMLMode(
                fileType: fileType, isSourceMode: isSourceMode,
                filePath: filePath, features: rendererFeatures
            ), let filePath {
                let pathChanged = filePath != lastDirectHTMLPath
                let contentChanged = contentRevision != lastRenderedContentRevision
                guard !isDirectHTMLMode || pathChanged || contentChanged else { return }
                // 初回ロード・ファイル切替では保存済みの per-file 倍率を使い、
                // ライブリロード（同一ファイルの content 変更）では現在の倍率を維持する。
                let isFirstLoadOrSwitch = !isDirectHTMLMode || pathChanged
                pendingPageZoom = isFirstLoadOrSwitch ? initialPageZoom : webView.pageZoom
                recordRendered(
                    contentRevision: contentRevision,
                    fileType: fileType, filePath: filePath
                )
                lastIsSourceMode = isSourceMode
                lastDirectHTMLPath = filePath
                isDirectHTMLMode = true
                webViewProxy?.isDirectHTMLMode = true
                isReady = false
                // 直接ロードする HTML 内の <script> 実行を無効化する（設計スコープ外）。
                webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = false
                webView.loadFileURL(filePath, allowingReadAccessTo: filePath.deletingLastPathComponent())
                return
            }

            // 直接 HTML モードから viewer.html モードへの復帰
            if isDirectHTMLMode {
                // この分岐に来る時点でファイルかモードが直接HTML状態と必ず異なるため
                // (同一なら上の直接HTMLロード分岐に吸収される)、常に切替として扱われる。
                let restoreFromPersistedPosition = Self.isFileOrModeSwitch(
                    filePath: filePath, isSourceMode: isSourceMode,
                    lastRenderedFilePath: lastRenderedFilePath, lastIsSourceMode: lastIsSourceMode
                )
                exitDirectHTMLMode(webView: webView) {
                    self.applyRender(
                        webView: webView, content: content, fileType: fileType,
                        filePath: filePath, isSourceMode: isSourceMode,
                        showLineNumbers: showLineNumbers,
                        truncation: truncation,
                        restoreFromPersistedPosition: restoreFromPersistedPosition
                    )
                }
                recordRendered(
                    contentRevision: contentRevision,
                    fileType: fileType, filePath: filePath
                )
                return
            }

            // content・fileType だけでなく isSourceMode の変化でも再描画する。
            // (例: notes.md → notes.txt のように内容が同じでも種別が変わる切替、
            // ソース/レンダリング表示の切替も同じ content から異なる文字列を描画し直す必要がある)
            let needsRender = contentRevision != lastRenderedContentRevision
                || fileType != lastRenderedFileType
                || showLineNumbers != lastShowLineNumbers
                || isSourceMode != lastIsSourceMode
                || truncation != lastTruncation
            guard needsRender else { return }

            let restoreFromPersistedPosition = Self.isFileOrModeSwitch(
                filePath: filePath, isSourceMode: isSourceMode,
                lastRenderedFilePath: lastRenderedFilePath, lastIsSourceMode: lastIsSourceMode
            )
            recordRendered(
                contentRevision: contentRevision,
                fileType: fileType, filePath: filePath
            )
            applyRender(
                webView: webView, content: content, fileType: fileType,
                filePath: filePath, isSourceMode: isSourceMode,
                showLineNumbers: showLineNumbers,
                truncation: truncation,
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
