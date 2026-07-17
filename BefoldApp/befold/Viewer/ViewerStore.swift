import BefoldKit
import Foundation

/// loadMoreLines() の結果。contentRevision は追記後の世代番号で、呼び出し側が
/// 描画済みキャッシュを同期し直後の全文 render 誤爆を防ぐために使う。
struct LoadMoreLinesResult: Equatable {
    let chunk: String
    let isTruncated: Bool
    let lineCount: Int
    let contentRevision: Int
    /// セッション途中のチャンク読込がエラーで打ち切られた場合 true。
    /// isTruncated は true のまま維持され(表示済みが全体ではないことを示すため)、
    /// このフラグでバナーを「正常な段階読込」ではなく「読込エラー」として区別する。
    let loadFailed: Bool
}

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
    typealias ChunkedReaderFactory = @Sendable (NormalizedTextCache, FileType) throws -> any ChunkedTextReading

    private(set) var content: String = ""
    /// content が更新されるたびに増分する世代番号。ViewerWebView.Coordinator が
    /// content 全文比較の代わりにこれで変更検知することで、文字列の重複保持を避ける。
    private(set) var contentRevision = 0
    private(set) var fileType: FileType = .mmd
    /// 開いたファイルが非対応内容と判定された場合に理由が入る。
    /// 非 nil の間 content は更新されない(バイナリを丸ごと文字列化しない)。
    private(set) var rejectReason: RejectReason?
    /// 行指向ファイルを段階読み込み中で、まだ末尾に達していない間 true になる。
    private(set) var isTruncated: Bool = false
    /// 直近のチャンク読込がエラーで打ち切られたかどうか。isTruncated=true のまま
    /// chunkSession が nil になるケースをバナー表示から区別するために使う。
    /// apply() の読み込み完了で false にリセットする(TASK-39)。
    private(set) var loadFailed: Bool = false
    /// 現在表示している累積行数(段階読み込みのバナー表示に使う)。
    private(set) var displayedLineCount: Int = 0
    /// 最新世代の読み込み(I/O・デコード・初回チャンク取得)が実行中かどうか。
    /// content はロード完了まで旧ファイルの表示を保持するため(task-32)、
    /// UI 側は content が空でまだ何も表示できていない間だけこれを見てインジケータを出す。
    private(set) var isLoading: Bool = false
    private(set) var filePath: URL?

    /// filePath が指す現在のファイルの種別。openFile / handleRename で filePath と同時に
    /// 即時更新する内部値。バックグラウンド読み込み(loadContent → computeLoad)へ渡すために使い、
    /// 公開の fileType とは異なりロード完了を待たない。
    /// 公開 fileType は apply() 内で content と同時にのみ更新する(このずれが task-32 の原因だった)。
    @ObservationIgnored private var pendingFileType: FileType = .mmd

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

    /// 前回適用したキャッシュの dataHash。同一内容スキップの比較に使う。
    @ObservationIgnored private var contentHash: Int?

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
        makeChunkedReader = chunkedReaderFactory ?? { cache, fileType in
            StringChunkReader(cache: cache, respectsCSVQuotes: fileType.csvDelimiter != nil)
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
        pendingFileType = FileType(url: url)
        loadContent()

        fileWatcher = makeWatcher(url, { [weak self] in
            self?.loadContent()
        }, { [weak self] newURL in
            self?.handleRename(to: newURL)
        })
    }

    /// 監視対象ファイルの rename / move を反映する。
    /// filePath を新 URL に更新し、コンテンツの再読込を予約したうえでウィンドウ側へ通知する。
    /// 公開 fileType は apply() で content と同時にのみ更新する(下の pendingFileType 参照)。
    private func handleRename(to newURL: URL) {
        filePath = newURL
        pendingFileType = FileType(url: newURL)
        loadContent()
        onFileRenamed?(newURL)
    }

    /// 次のチャンクを読み込んで content に追記し、表示状態を返す。
    /// 末尾に達している・セッションがない場合は nil を返す。
    /// 戻り値の contentRevision は追記後の世代番号(呼び出し側が描画済みキャッシュを
    /// 同期し、直後の全文 render 誤爆を防ぐために使う)。
    func loadMoreLines() async -> LoadMoreLinesResult? {
        guard isTruncated, let session = chunkSession else { return nil }
        do {
            let result = try await session.readNextChunk()
            // 読み込み待機中の再読込(セッション交代)と競合した場合は、
            // 古いセッションの結果を捨てて新しい表示を壊さない。
            guard chunkSession === session else { return nil }
            content += result.text
            contentRevision += 1
            isTruncated = !result.isAtEnd
            newlineCount += result.text.utf8.count(where: { $0 == 0x0A })
            updateDisplayedLineCount()
            return LoadMoreLinesResult(
                chunk: result.text, isTruncated: isTruncated,
                lineCount: displayedLineCount, contentRevision: contentRevision,
                loadFailed: false
            )
        } catch {
            guard chunkSession === session else { return nil }
            // セッション途中のエラーではチャンクセッションを終了し、
            // 表示済みの内容を保持する。loadContent で全体を再読込すると、
            // 10MB 超のファイルで表示済みコンテンツが fileTooLarge に置き換わるため。
            // isTruncated は true のまま維持する: 正常な EOF(バナーを消す)と
            // エラー打ち切り(バナーをエラー表示に切り替える)を区別するため、
            // loadFailed だけで判別させる。
            chunkSession = nil
            loadFailed = true
            return LoadMoreLinesResult(
                chunk: "", isTruncated: isTruncated,
                lineCount: displayedLineCount, contentRevision: contentRevision,
                loadFailed: true
            )
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
        isLoading = true
        let resolved = filePath.resolvingSymlinksInPath()
        let fileType = pendingFileType
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
        apply(outcome, fileType: fileType)
    }

    /// バックグラウンド読み込みの結果。メインアクターへ持ち帰って一括適用する。
    private enum LoadOutcome: Sendable {
        /// ファイルが存在しない(削除グレース期間を開始する)。
        case missing
        /// 行指向ファイルのチャンクセッションを開始し、先頭チャンクを読み込んだ。
        case chunked(session: any ChunkedTextReading, cache: NormalizedTextCache, firstChunk: String, isAtEnd: Bool)
        /// 全量読み込みの結果(rejectReason を含みうる)。
        case full(ContentLoader.LoadedContent, cache: NormalizedTextCache?)
    }

    /// ファイルの存在確認・NormalizedTextCache 生成・チャンクセッション生成・全量読み込みを行う。
    /// nonisolated async のため呼び出し元のアクターを離れて実行され、
    /// I/O・デコードがメインスレッドを塞がない。
    private nonisolated static func computeLoad(
        resolved: URL,
        fileType: FileType,
        fileReader: any FileReading,
        contentLoader: ContentLoader,
        chunkedReaderFactory: ChunkedReaderFactory
    ) async -> LoadOutcome {
        guard fileReader.fileExists(at: resolved) else { return .missing }

        if fileType.isBinaryContent {
            return .full(contentLoader.load(from: resolved, fileType: fileType), cache: nil)
        }

        if fileReader.isBinary(at: resolved) {
            return .full(
                ContentLoader.LoadedContent(rejectReason: .unsupportedFormat, content: ""),
                cache: nil
            )
        }

        let sizeLimit = fileType.isLineOriented
            ? NormalizedTextCache.maxFileSizeBytes
            : ContentLoader.maxTextFileSizeBytes
        if let size = fileReader.fileSize(at: resolved), size > sizeLimit {
            return .full(
                ContentLoader.LoadedContent(rejectReason: .fileTooLarge, content: ""),
                cache: nil
            )
        }

        do {
            let data = try fileReader.readData(from: resolved)
            let cache = try NormalizedTextCache(data: data)

            if fileType.isLineOriented {
                let reader = try chunkedReaderFactory(cache, fileType)
                let firstChunk = try await reader.readNextChunk()
                return .chunked(
                    session: reader, cache: cache,
                    firstChunk: firstChunk.text, isAtEnd: firstChunk.isAtEnd
                )
            } else {
                if cache.text.utf8.count > ContentLoader.maxTextFileSizeBytes {
                    return .full(
                        ContentLoader.LoadedContent(rejectReason: .fileTooLarge, content: ""),
                        cache: nil
                    )
                }
                return .full(
                    ContentLoader.LoadedContent(rejectReason: nil, content: cache.text),
                    cache: cache
                )
            }
        } catch {
            if !fileReader.fileExists(at: resolved) { return .missing }
            // 事前サイズチェックをすり抜けた場合(fileSize が nil を返した、または
            // チェック後にファイルが肥大化した TOCTOU)、NormalizedTextCache.init が
            // fileTooLarge を投げる。これを unsupportedFormat に丸めず理由を保持する。
            let reason: RejectReason = error is NormalizedTextCacheError ? .fileTooLarge : .unsupportedFormat
            return .full(
                ContentLoader.LoadedContent(rejectReason: reason, content: ""),
                cache: nil
            )
        }
    }

    /// 読み込み結果を表示状態(fileType / content / rejectReason / isTruncated / 行数カウンタ /
    /// chunkSession)へ一括適用する。表示状態のタプルを書き換えるのはここだけにする。
    /// fileType を content と同時にここで確定させることで、旧ファイルの content に
    /// 新ファイルの fileType が組み合わさった中間状態が描画されないようにする(task-32)。
    private func apply(_ outcome: LoadOutcome, fileType: FileType) {
        isLoading = false
        switch outcome {
        case .missing:
            scheduleFileGone()
            return
        case let .chunked(session, cache, firstChunk, isAtEnd):
            if cache.dataHash == contentHash, fileType == self.fileType, !loadFailed {
                return
            }
            self.fileType = fileType
            contentHash = cache.dataHash
            chunkSession = session
            rejectReason = nil
            isTruncated = !isAtEnd
            loadFailed = false
            content = firstChunk
            contentRevision += 1
            newlineCount = firstChunk.utf8.count(where: { $0 == 0x0A })
            updateDisplayedLineCount()
        case let .full(loaded, cache):
            if let cache, cache.dataHash == contentHash, fileType == self.fileType, !loadFailed {
                return
            }
            self.fileType = fileType
            contentHash = cache?.dataHash
            chunkSession = nil
            rejectReason = loaded.rejectReason
            isTruncated = false
            loadFailed = false
            content = loaded.content
            contentRevision += 1
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
        isLoading = false
        fileGoneTask?.cancel()
        fileGoneTask = nil
        chunkSession = nil
        fileWatcher?.stop()
        fileWatcher = nil
    }
}
