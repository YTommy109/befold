import BefoldKit
import Foundation

/// ビューアの表示状態を管理する。
/// ファイルの読み込み・監視・削除検知を行い、UI にバインドされるプロパティを更新する。
/// 読み込み(I/O・デコード)はバックグラウンドで行い、結果だけをメインアクターで適用する。
@MainActor
@Observable
final class ViewerStore {
    typealias WatcherFactory = @MainActor @Sendable (
        URL,
        @escaping @MainActor @Sendable () -> Void,
        (@MainActor @Sendable (URL) -> Void)?
    ) -> FileWatching

    /// チャンクリーダーの生成(ファイルを開いて先頭をプローブする)はバックグラウンドの
    /// 読み込みタスクから呼ばれるため、メインアクター隔離にしない。
    typealias ChunkedReaderFactory = @Sendable (URL, FileType) throws -> any ChunkedTextReading

    private(set) var content: String = ""
    private(set) var fileType: FileType = .mmd
    /// 開いたファイルが非対応内容と判定された場合に理由が入る。
    /// 非 nil の間 content は更新されない(バイナリを丸ごと文字列化しない)。
    private(set) var rejectReason: RejectReason?
    /// 行指向ファイルを段階読み込み中で、まだ末尾に達していない間 true になる。
    private(set) var isTruncated: Bool = false
    /// 現在表示している累積行数(段階読み込みのバナー表示に使う)。
    private(set) var displayedLineCount: Int = 0
    private(set) var filePath: URL?

    /// 開いたファイルが非対応と判定されているかどうか。
    var isRejected: Bool {
        rejectReason != nil
    }

    /// ソース表示中かどうか。HTML 直接ロードモードでは、変更が SwiftUI の
    /// 更新サイクルをトリガーし ViewerWebView.updateContent での分岐に使われる。
    var isSourceMode: Bool = false

    /// 開いているファイルが rename / move されたときに新 URL を通知する。
    /// ウィンドウ側がタイトル・representedURL・セッション記録を更新するために使う。
    var onFileRenamed: ((URL) -> Void)?

    /// 監視中のファイルが削除されたことが確定したときに呼ばれるコールバック。
    /// グレース期間(1 秒)中に再作成されなかった場合に発火する。
    var onFileGone: (@MainActor @Sendable () -> Void)?

    /// 開いたままのファイルが内容を再読込した(FileWatcher 経由の変更検知・rename)ときに
    /// 呼ばれるコールバック。rejectReason / showsCodeContent など読み込みが
    /// 確定させた表示状態を、AppKit ツールバー側に追従させるために使う。
    /// 読み込みは非同期のため、openFile / 監視コールバックからは遅れて発火する。
    var onContentReloaded: (() -> Void)?

    /// 実行中の非同期読み込みタスク。テストと loadMoreLines のエラー復旧が完了を待つために公開する。
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?

    /// 読み込みの世代番号。loadContent が予約されるたびに進み、
    /// 追い越された古い読み込み結果(stale outcome)の適用を防ぐ。
    @ObservationIgnored private var loadGeneration = 0

    /// 削除確認のグレース期間タスク。再作成されたらキャンセルする。
    private var fileGoneTask: Task<Void, Never>?

    /// 段階読み込み中の行チャンクセッション。ファイル再読込・close でリセットする。
    private var chunkSession: (any ChunkedTextReading)?

    /// 蓄積済み content に含まれる改行の数(displayedLineCount の増分計算用)。
    @ObservationIgnored private var newlineCount: Int = 0

    private var fileWatcher: FileWatching?
    private let makeWatcher: WatcherFactory
    private let makeChunkedReader: ChunkedReaderFactory
    private let fileReader: any FileReading
    private let contentLoader: ContentLoader
    private let defaults: UserDefaults
    /// グレース期間の待機に使うクロック。テストでは仮想時刻を注入して実時間依存を排除する。
    private let clock: any Clock<Duration>

    private static let showLineNumbersKey = "ShowLineNumbers"

    /// 行番号付きコード表示を有効にするかどうか。UserDefaults に永続化される。
    var showLineNumbers: Bool {
        didSet {
            defaults.set(showLineNumbers, forKey: Self.showLineNumbersKey)
        }
    }

    /// コード表示中(ソースモードまたはコード形式ファイル)かどうか。
    /// トップバーの表示可否と行番号メニューの有効判定が共有する。
    var showsCodeContent: Bool {
        if isRejected { return false }
        if isSourceMode { return true }
        if case .code = fileType { return true }
        return false
    }

    init(
        watcherFactory: WatcherFactory? = nil,
        fileReader: any FileReading = DefaultFileReader(),
        chunkedReaderFactory: ChunkedReaderFactory? = nil,
        defaults: UserDefaults = .standard,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.defaults = defaults
        makeWatcher = watcherFactory ?? { url, onChange, onRename in
            FileWatcher(path: url, onChange: onChange, onRename: onRename)
        }
        makeChunkedReader = chunkedReaderFactory ?? { url, fileType in
            try LineChunkReader(url: url, respectsCSVQuotes: fileType.csvDelimiter != nil)
        }
        self.fileReader = fileReader
        contentLoader = ContentLoader(fileReader: fileReader)
        self.clock = clock
        _showLineNumbers = defaults.bool(forKey: Self.showLineNumbersKey)
    }

    /// 指定 URL のファイルを開き、ファイル監視を開始する。
    /// 既に別のファイルを開いている場合は、先に監視を停止してから切り替える。
    func openFile(_ url: URL) {
        fileGoneTask?.cancel()
        fileGoneTask = nil
        fileWatcher?.stop()
        filePath = url
        fileType = FileType(url: url)
        loadContent()

        fileWatcher = makeWatcher(url, { [weak self] in
            self?.loadContent()
        }, { [weak self] newURL in
            self?.handleRename(to: newURL)
        })
    }

    /// 監視対象ファイルの rename / move を反映する。
    /// filePath / fileType を新 URL に更新し、コンテンツの再読込を予約したうえでウィンドウ側へ通知する。
    private func handleRename(to newURL: URL) {
        filePath = newURL
        fileType = FileType(url: newURL)
        loadContent()
        onFileRenamed?(newURL)
    }

    /// 次のチャンクを読み込んで content に追記し、表示状態を返す。
    /// 末尾に達している・セッションがない場合は nil を返す。
    func loadMoreLines() async -> (chunk: String, isTruncated: Bool, lineCount: Int)? {
        guard isTruncated, let session = chunkSession else { return nil }
        do {
            let result = try await session.readNextChunk()
            // 読み込み待機中の再読込(セッション交代)と競合した場合は、
            // 古いセッションの結果を捨てて新しい表示を壊さない。
            guard chunkSession === session else { return nil }
            content += result.text
            isTruncated = !result.isAtEnd
            newlineCount += result.text.utf8.count(where: { $0 == 0x0A })
            updateDisplayedLineCount()
            return (result.text, isTruncated, displayedLineCount)
        } catch {
            guard chunkSession === session else { return nil }
            // セッション途中のエラーではチャンクセッションを終了し、
            // 表示済みの内容を保持する。loadContent で全体を再読込すると、
            // 10MB 超のファイルで表示済みコンテンツが fileTooLarge に置き換わるため。
            chunkSession = nil
            isTruncated = false
            return ("", false, displayedLineCount)
        }
    }

    /// 蓄積済み content の改行数から表示行数を再計算する。
    /// 末尾が改行で終わらない場合、その途中の行(強制分割チャンク末尾・最終行)も
    /// 表示中の 1 行として数える(改行なしの巨大単一行が「0 行」と表示されないように)。
    private func updateDisplayedLineCount() {
        displayedLineCount = newlineCount + (!content.isEmpty && content.utf8.last != 0x0A ? 1 : 0)
    }

    /// 現在の filePath の読み込みを予約する。I/O・デコードはバックグラウンドで行い、
    /// 完了後にメインアクターで表示状態へ一括適用する。呼び出しごとに世代番号を進め、
    /// 追い越された古い読み込みの結果は破棄する。
    private func loadContent() {
        guard let filePath else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let resolved = filePath.resolvingSymlinksInPath()
        let fileType = fileType
        loadTask = Task {
            await self.performLoad(
                resolved: resolved, fileType: fileType,
                generation: generation
            )
        }
    }

    /// バックグラウンドで読み込み結果を計算し、世代が最新のままなら表示状態へ適用する。
    private func performLoad(
        resolved: URL, fileType: FileType, generation: Int
    ) async {
        let outcome = await Self.computeLoad(
            resolved: resolved,
            fileType: fileType,
            fileReader: fileReader,
            contentLoader: contentLoader,
            chunkedReaderFactory: makeChunkedReader
        )
        // close() でキャンセルされた、または新しい読み込みに追い越された結果は捨てる。
        guard !Task.isCancelled, generation == loadGeneration else { return }
        apply(outcome)
    }

    /// バックグラウンド読み込みの結果。メインアクターへ持ち帰って一括適用する。
    private enum LoadOutcome: Sendable {
        /// ファイルが存在しない(削除グレース期間を開始する)。
        case missing
        /// 行指向ファイルのチャンクセッションを開始し、先頭チャンクを読み込んだ。
        case chunked(session: any ChunkedTextReading, firstChunk: String, isAtEnd: Bool)
        /// 全量読み込みの結果(rejectReason を含みうる)。
        case full(ContentLoader.LoadedContent)
        /// 読み込み前の判定で非対応が確定した。
        case rejected(RejectReason)
    }

    /// ファイルの存在確認・チャンクセッション生成・全量読み込みを行う。
    /// nonisolated async のため呼び出し元のアクターを離れて実行され、
    /// 最大 4MB の I/O・デコードがメインスレッドを塞がない。
    private nonisolated static func computeLoad(
        resolved: URL,
        fileType: FileType,
        fileReader: any FileReading,
        contentLoader: ContentLoader,
        chunkedReaderFactory: ChunkedReaderFactory
    ) async -> LoadOutcome {
        guard fileReader.fileExists(at: resolved) else { return .missing }

        if fileType.isLineOriented {
            do {
                let reader = try chunkedReaderFactory(resolved, fileType)
                let firstChunk = try await reader.readNextChunk()
                return .chunked(
                    session: reader, firstChunk: firstChunk.text, isAtEnd: firstChunk.isAtEnd
                )
            } catch {
                if !fileReader.fileExists(at: resolved) { return .missing }
                return .rejected(.unsupportedFormat)
            }
        }
        return .full(contentLoader.load(from: resolved, fileType: fileType))
    }

    /// 読み込み結果を表示状態(content / rejectReason / isTruncated / 行数カウンタ /
    /// chunkSession)へ一括適用する。表示状態のタプルを書き換えるのはここだけにする。
    private func apply(_ outcome: LoadOutcome) {
        switch outcome {
        case .missing:
            scheduleFileGone()
            return
        case let .chunked(session, firstChunk, isAtEnd):
            chunkSession = session
            rejectReason = nil
            isTruncated = !isAtEnd
            content = firstChunk
            newlineCount = firstChunk.utf8.count(where: { $0 == 0x0A })
            updateDisplayedLineCount()
        case let .full(loaded):
            chunkSession = nil
            rejectReason = loaded.rejectReason
            isTruncated = false
            content = loaded.content
            newlineCount = 0
            displayedLineCount = 0
        case let .rejected(reason):
            chunkSession = nil
            rejectReason = reason
            isTruncated = false
            content = ""
            newlineCount = 0
            displayedLineCount = 0
        }
        fileGoneTask?.cancel()
        fileGoneTask = nil
        // rejectReason / content(表示状態)が確定した後に通知する。
        onContentReloaded?()
    }

    /// グレース期間後にファイルの不在を再確認し、確定したら onFileGone を発火する。
    /// 常に張り直す(古いタスクをキャンセルして置き換える)ことで、発火せず完了した
    /// タスクが残って以後の検知を塞ぐことを防ぐ。
    ///
    /// FileWatcher のデバウンス(0.2s) + 余裕を持たせた期間を設定し、
    /// 環境依存のタイミング問題による検知遅延に対応する。
    ///
    /// 注: filePath は schedule 時点でキャプチャせず、発火時に再確認する。
    /// handleRename で filePath が更新されると、rename と grace period の競争状態で
    /// 新しいパスが存在する場合、ウィンドウを閉じずに監視を継続するため。
    private func scheduleFileGone() {
        fileGoneTask?.cancel()
        fileGoneTask = Task { @MainActor [weak self, clock] in
            try? await clock.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            guard let filePath else { return }
            guard !fileReader.fileExists(at: filePath.resolvingSymlinksInPath()) else { return }
            onFileGone?()
        }
    }

    /// ファイル監視を停止し、リソースを解放する。
    func close() {
        loadTask?.cancel()
        loadTask = nil
        fileGoneTask?.cancel()
        fileGoneTask = nil
        chunkSession = nil
        fileWatcher?.stop()
        fileWatcher = nil
    }
}
