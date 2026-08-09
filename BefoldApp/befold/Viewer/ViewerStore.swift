import BefoldKit
import Foundation

/// ビューアの表示状態を管理する。
/// ファイルの読み込み・監視・削除検知を行い、UI にバインドされるプロパティを更新する。
/// 読み込み(I/O・デコード)はバックグラウンドで行い、結果だけをメインアクターで適用する。
@MainActor
@Observable
final class ViewerStore {
    /// debounceDelay を引数に含めることで、fileGoneGracePeriod の導出元(watcherDebounceDelay)と
    /// 実際に watcher が使う debounce を型で一致させる(呼び出し側の「揃える」努力に頼らない)。
    typealias WatcherFactory = @MainActor @Sendable (
        URL,
        TimeInterval,
        @escaping @MainActor @Sendable () -> Void,
        (@MainActor @Sendable (URL) -> Void)?
    ) -> FileWatching

    /// チャンクリーダーの生成(ファイルを開いて先頭をプローブする)はバックグラウンドの
    /// 読み込みタスクから呼ばれるため、メインアクター隔離にしない。
    typealias ChunkedReaderFactory = ViewerLoadPipeline.ChunkedReaderFactory

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
    /// apply() の読み込み完了で false にリセットする。
    private(set) var loadFailed: Bool = false
    /// 現在表示している累積行数(段階読み込みのバナー表示に使う)。
    private(set) var displayedLineCount: Int = 0
    /// 最新世代の読み込み(I/O・デコード・初回チャンク取得)が実行中かどうか。
    /// content はロード完了まで旧ファイルの表示を保持するため、
    /// UI 側は content が空でまだ何も表示できていない間だけこれを見てインジケータを出す。
    private(set) var isLoading: Bool = false
    private(set) var filePath: URL?
    /// HTML の charset 宣言(BOM/meta charset)有無。HTML 直接ロードモードで
    /// webView.load(正規化文字列を注入)/loadFileURL(WebKit に委ねる)を分岐するために使う。
    /// fileType が .html 以外、またはロード失敗時は nil。
    private(set) var hasDeclaredHTMLCharset: Bool?

    /// openFile / handleRename で即時更新する、読み込み対象の URL。バックグラウンド読み込み
    /// (loadContent → performLoad)へ渡すために使い、公開の filePath とは異なりロード完了を待たない。
    /// 公開 filePath は apply() 内で fileType / content と同時にのみ更新する(下記 pendingFileType 参照)。
    @ObservationIgnored private var pendingURL: URL?

    /// 現在の対象ファイル URL の唯一の保持先。openFile / handleRename で即時に更新される
    /// (pendingURL と同値)。ウィンドウ層(ViewerWindowController)はこれを参照し、URL を
    /// 二重に保持しない。公開 filePath はロード完了後にのみ更新される点で異なる。
    var currentURL: URL? {
        pendingURL
    }

    /// 対象ファイル URL を差し替える唯一の入口。値(パスのバイト列)は変えずに、
    /// 文字列の裏打ちだけ native な連続 UTF-8 へ揃える。
    ///
    /// 開く対象は CLI 引数・セッション復元・Quick Open・フォルダー解決(resolveFileToOpen)と
    /// 出所がばらばらで、FileManager 由来のものは NSString 裏打ちのまま入ってくる。
    /// この URL はサイドバーの選択や一覧の行と突き合わされ、URL のハッシュ・等値を通る。
    /// 消費側それぞれが防御的に揃え直すのではなく、文書 URL の保持先であるここで
    /// 1 度だけ揃える(TASK-279)。
    private func setPendingURL(_ url: URL) {
        pendingURL = url.nativeBackedFileURL
    }

    /// pendingURL が指す読み込み対象ファイルの種別。openFile / handleRename で pendingURL と
    /// 同時に即時更新する内部値。バックグラウンド読み込み(loadContent → performLoad)へ渡すために使い、
    /// 公開の fileType とは異なりロード完了を待たない。
    /// 公開 fileType は apply() 内で filePath / content と同時にのみ更新する
    /// (filePath だけ先行して変わると、旧ファイルの fileType に新ファイルの filePath が
    /// 組み合わさった中間状態が描画されてしまうため)。
    @ObservationIgnored private var pendingFileType: FileType = .mmd

    /// 開いたファイルが非対応と判定されているかどうか。
    var isRejected: Bool {
        rejectReason != nil
    }

    /// プレビューエリアの表示モード（レンダリング / ソース / 差分）。
    /// 変更が SwiftUI の更新サイクルをトリガーし、ViewerWebView.updateContent での
    /// 分岐（HTML 直接ロード判定など）と差分の描画可否に使われる。
    ///
    /// ソース表示と差分表示を別々の Bool で持たないのは、`.rendered` なのに差分だけ ON という
    /// 不整合を状態として作れなくするため（`ViewerDisplayMode` の doc を参照）。
    var displayMode: ViewerDisplayMode = .rendered

    /// ソース表示中かどうか。レンダラ境界へ渡す Bool はここから導出する。
    var isSourceMode: Bool {
        displayMode.isSourceMode
    }

    /// git 差分を重ねて表示するモードかどうか。実際に差分が描けるかは `diffText` の有無にもよる。
    var showsDiff: Bool {
        displayMode.showsDiff
    }

    /// モード切替セグメント・メニューのチェックが指し示すべきモード。
    ///
    /// プレビューを持たない種別(.code)は `displayMode` が `.rendered` のままでも実際には
    /// ソースを出している。保存値としての `.rendered` をそのまま選択位置に使うと、
    /// 選べない(無効な)レンダリングセグメントが選択済みに見える。表示のためだけの導出で、
    /// 保存値は書き換えない。
    var effectiveDisplayMode: ViewerDisplayMode {
        if displayMode == .rendered, showsCodeContent { return .source }
        return displayMode
    }

    /// ソース表示へ重ねる git 差分の本文（unified diff）。取得は
    /// `ViewerWindowController` が行い、ここへ結果だけを置く。差分が無い・
    /// 取得できない・機能が無効ならすべて nil で、表示は通常のソース表示になる。
    ///
    /// 値は常に「いま開いているファイル」の差分であり、対象が変わる `openFile` で
    /// 捨てる。取得は非同期なので、着地時の URL 一致確認（呼び出し側）だけでは
    /// 切替直後に前のファイルの差分が残る（開始時の無効化と着地時の確認は別物）。
    var diffText: String?

    /// 開いているファイルが rename / move されたときに旧 URL と新 URL を通知する。
    /// ウィンドウ側がタイトル・representedURL・セッション記録・per-file 状態の移行を
    /// 更新するために使う。旧 URL は store が握る唯一の現在 URL(currentURL)であり、
    /// ウィンドウ側で別途保持しないよう通知に含める。
    var onFileRenamed: ((_ oldURL: URL, _ newURL: URL) -> Void)?

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
    /// makeWatcher(openFile 時)へ渡す debounce 間隔。fileGoneGracePeriod の導出元でもある。
    private let watcherDebounceDelay: TimeInterval
    private let makeChunkedReader: ChunkedReaderFactory
    /// 注入された fileReader。ウィンドウ層(ViewerWindowController)が pathResolver の構築に
    /// 同一インスタンスを共有できるよう、fileExists/isExistingFile 越しだけでなく直接公開する。
    let fileReader: any FileReading
    private let contentLoader: ContentLoader
    private let defaults: UserDefaults
    /// グレース期間の待機に使うクロック。テストでは仮想時刻を注入して実時間依存を排除する。
    private let clock: any Clock<Duration>
    /// FileWatcher のデバウンス既定値に余裕を持たせたグレース期間。
    /// 環境依存のタイミング問題による検知遅延に対応する。
    /// watcherFactory に注入された debounce 間隔から導出するため、テストで短い debounce を
    /// 注入すればグレース期間も自動的に短縮される(プロダクト既定 0.2s なら従来どおり 1.0s)。
    private let fileGoneGracePeriod: TimeInterval

    private static let showLineNumbersKey = "ShowLineNumbers"

    /// applyShowLineNumbersOverride 実行中だけ true になり、didSet の永続化書き込みを抑止する。
    private var suppressShowLineNumbersPersistence = false

    /// 行番号付きコード表示を有効にするかどうか。UserDefaults に永続化される。
    var showLineNumbers: Bool {
        didSet {
            guard !suppressShowLineNumbersPersistence else { return }
            defaults.set(showLineNumbers, forKey: Self.showLineNumbersKey)
        }
    }

    /// 表示中の文書のライブな倍率。**窓が生きている間はこの値が有効**で、ファイル単位の
    /// 保存値(`ZoomStore`)は「次にその文書を開くときの既定値」にすぎない
    /// (ADR 0002「文書の状態の規則」)。保存値を読んでここへ入れるのは、窓がその文書を
    /// 提示し始めるとき(オープン・ファイル切替)だけ。生きている窓が読み直すと、
    /// 他窓の操作が後から効いてしまう。
    var zoom: Double = ZoomStore.defaultZoom

    /// 次にファイル/モードの切替で描画するとき、JS へ渡すスクロール復元位置。
    /// `zoom` と同じ規則で、提示開始(オープン・ファイル切替・モード切替)のときだけ
    /// 保存値(`ScrollPositionStore`)から入れる。
    var scrollPositionToRestore: Double = 0

    /// コード表示中(ソースモードまたはコード形式ファイル)かどうか。
    /// トップバーの表示可否と行番号メニューの有効判定が共有する。
    var showsCodeContent: Bool {
        if isRejected { return false }
        if isSourceMode { return true }
        if case .code = fileType { return true }
        return false
    }

    /// - Parameter watcherDebounceDelay: makeWatcher(openFile 時)へ渡す debounce 間隔。
    ///   fileGoneGracePeriod(この値の 5 倍)の導出にも使うため、実際に watcher が使う
    ///   debounce と乖離しない(WatcherFactory の引数として型で渡すため、値の不一致は起きない)。
    init(
        watcherFactory: WatcherFactory? = nil,
        watcherDebounceDelay: TimeInterval = FileWatcher.defaultDebounceDelay,
        fileReader: any FileReading = DefaultFileReader(),
        chunkedReaderFactory: ChunkedReaderFactory? = nil,
        defaults: UserDefaults = .standard,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.defaults = defaults
        makeWatcher = watcherFactory ?? { url, debounceDelay, onChange, onRename in
            FileWatcher(path: url, debounceDelay: debounceDelay, onChange: onChange, onRename: onRename)
        }
        self.watcherDebounceDelay = watcherDebounceDelay
        makeChunkedReader = chunkedReaderFactory ?? ViewerLoadPipeline.defaultChunkedReaderFactory
        self.fileReader = fileReader
        contentLoader = ContentLoader(fileReader: fileReader)
        self.clock = clock
        fileGoneGracePeriod = watcherDebounceDelay * 5
        _showLineNumbers = defaults.bool(forKey: Self.showLineNumbersKey)
    }

    /// CLI の `--line-numbers`/`--no-line-numbers` から渡される、この起動限りの上書きを適用する。
    /// showLineNumbers の didSet(UserDefaults への永続化)を経由しないため、保存済みの
    /// グローバル設定は書き換えない。store が呼び出し元から明示注入された場合でも、
    /// この起動限りの上書きが確実に反映されるよう、store 生成後に呼び出す想定。
    func applyShowLineNumbersOverride(_ value: Bool) {
        suppressShowLineNumbersPersistence = true
        showLineNumbers = value
        suppressShowLineNumbersPersistence = false
    }

    /// 指定 URL のファイルを開き、ファイル監視を開始する。
    /// 既に別のファイルを開いている場合は、先に監視を停止してから切り替える。
    func openFile(_ url: URL) {
        fileGoneTask?.cancel()
        fileGoneTask = nil
        fileWatcher?.stop()
        // 差分は表示中ファイルに紐づくため、対象が変わった時点で捨てる。
        // 取得は非同期で、着地までの間ここに残っていると前のファイルの差分が
        // 新しいファイルの内容として描画される。
        diffText = nil
        setPendingURL(url)
        pendingFileType = FileType(url: url)
        loadContent()

        fileWatcher = makeWatcher(url, watcherDebounceDelay, { [weak self] in
            self?.loadContent()
        }, { [weak self] newURL in
            self?.handleRename(to: newURL)
        })
    }

    /// 注入された fileReader を通したファイル存在確認(ディレクトリを含む)。
    /// ウィンドウ層(ViewerWindowController)の switch/rename/リンク遷移の存在ガードが
    /// 静的な DefaultFileReader を直接叩かず、store と同一の fileReader を共有できるようにする
    /// (テストで InMemoryFileReader を注入した store 経由でモック化するため)。
    func fileExists(at url: URL) -> Bool {
        fileReader.fileExists(at: url)
    }

    /// 注入された fileReader を通した「存在する通常ファイル(ディレクトリでない)」判定。
    /// 用途は fileExists(at:) と同じく存在ガードの fileReader 共有。
    func isExistingFile(at url: URL) -> Bool {
        fileReader.isExistingFile(at: url)
    }

    /// 監視対象ファイルの rename / move を反映する。
    /// コンテンツの再読込を予約したうえでウィンドウ側へ通知する。公開 filePath / fileType は
    /// apply() で content と同時にのみ更新する(上の pendingURL / pendingFileType 参照)。
    private func handleRename(to newURL: URL) {
        let oldURL = pendingURL
        setPendingURL(newURL)
        pendingFileType = FileType(url: newURL)
        loadContent()
        if let oldURL {
            onFileRenamed?(oldURL, newURL)
        }
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

    /// 蓄積済み content の改行数から表示行数を再計算する。数え方の規則は
    /// DisplayedLineCount(1 回描画ホストと共有する単一情報源)に委ねる。
    private func updateDisplayedLineCount() {
        displayedLineCount = DisplayedLineCount.count(newlines: newlineCount, in: content)
    }

    /// pendingURL の読み込みを予約する。I/O・デコードはバックグラウンドで行い、
    /// 完了後にメインアクターで表示状態へ一括適用する。呼び出しごとに世代番号を進め、
    /// 追い越された古い読み込みの結果は破棄する。
    private func loadContent() {
        guard let target = pendingURL else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        let resolved = target.resolvingSymlinksInPath()
        let fileType = pendingFileType
        loadTask = Task {
            await self.performLoad(
                resolved: resolved, url: target, fileType: fileType,
                generation: generation
            )
        }
    }

    /// バックグラウンドで読み込み結果を計算し、世代が最新のままなら表示状態へ適用する。
    private func performLoad(
        resolved: URL, url: URL, fileType: FileType, generation: Int
    ) async {
        let outcome = await ViewerLoadPipeline.load(
            resolved: resolved,
            fileType: fileType,
            fileReader: fileReader,
            contentLoader: contentLoader,
            chunkedReaderFactory: makeChunkedReader
        )
        // close() でキャンセルされた、または新しい読み込みに追い越された結果は捨てる。
        guard !Task.isCancelled, generation == loadGeneration else { return }
        apply(outcome, url: url, fileType: fileType)
    }

    /// 読み込み結果を表示状態(filePath / fileType / content / rejectReason / isTruncated /
    /// 行数カウンタ / chunkSession)へ一括適用する。読み込み結果の種別ごとの差分は
    /// DisplayState の組み立てだけに閉じ込め、実際の書き換えは applyDisplayState に一本化する。
    /// filePath / fileType を content と同時にここで確定させることで、旧ファイルの content に
    /// 新ファイルの filePath や fileType が組み合わさった中間状態が描画されないようにする
    /// (task: HTML 表示直後の切替で空白表示になる不具合の再発防止)。
    private func apply(_ outcome: ViewerLoadPipeline.Outcome, url: URL, fileType: FileType) {
        isLoading = false
        filePath = url
        let state: DisplayState
        switch outcome {
        case .missing:
            scheduleFileGone()
            return
        case let .chunked(session, cache, firstChunk, isAtEnd):
            state = DisplayState(
                fileType: fileType,
                contentHash: cache.dataHash,
                chunkSession: session,
                rejectReason: nil,
                isTruncated: !isAtEnd,
                content: firstChunk,
                tracksLineCount: true,
                hasDeclaredHTMLCharset: nil
            )
        case let .full(loaded, cache):
            state = DisplayState(
                fileType: fileType,
                contentHash: cache?.dataHash,
                chunkSession: nil,
                rejectReason: loaded.rejectReason,
                isTruncated: false,
                content: loaded.content,
                tracksLineCount: false,
                hasDeclaredHTMLCharset: loaded.hasDeclaredHTMLCharset
            )
        }
        guard applyDisplayState(state) else { return }
        fileGoneTask?.cancel()
        fileGoneTask = nil
        // rejectReason / content(表示状態)が確定した後に通知する。
        onContentReloaded?()
    }

    /// apply() が一括適用する表示状態の組。読み込み結果の種別(.chunked / .full)ごとに
    /// 値を詰め替えるだけにして、フィールドを増やしたときに片方の分岐だけ更新し忘れる
    /// 事故を構造的に防ぐ。
    private struct DisplayState {
        let fileType: FileType
        /// 同一内容スキップの比較に使う dataHash。全文読込でキャッシュがない場合は nil。
        let contentHash: Int?
        let chunkSession: (any ChunkedTextReading)?
        let rejectReason: RejectReason?
        let isTruncated: Bool
        let content: String
        /// content から行数カウンタを追従させるかどうか。段階読み込み(.chunked)は
        /// バナー表示に行数を使うため true、全文読込は行数を表示しないため false
        /// (カウンタは 0 にリセットされる)。
        let tracksLineCount: Bool
        /// HTML の charset 宣言有無。.chunked(HTML は非対応)は常に nil。
        let hasDeclaredHTMLCharset: Bool?
    }

    /// 表示状態を一括更新する。同一内容(dataHash・fileType が一致し、直前のチャンク読込も
    /// 失敗していない)の再読込では何も書き換えず false を返す。
    /// 表示状態のタプルを書き換えるのはこのメソッドだけにする。
    private func applyDisplayState(_ state: DisplayState) -> Bool {
        if let newHash = state.contentHash,
           newHash == contentHash, state.fileType == fileType, !loadFailed
        {
            return false
        }
        fileType = state.fileType
        contentHash = state.contentHash
        chunkSession = state.chunkSession
        rejectReason = state.rejectReason
        isTruncated = state.isTruncated
        loadFailed = false
        content = state.content
        hasDeclaredHTMLCharset = state.hasDeclaredHTMLCharset
        contentRevision += 1
        if state.tracksLineCount {
            newlineCount = state.content.utf8.count(where: { $0 == 0x0A })
            updateDisplayedLineCount()
        } else {
            newlineCount = 0
            displayedLineCount = 0
        }
        return true
    }

    /// グレース期間後にファイルの不在を再確認し、確定したら onFileGone を発火する。
    /// 常に張り直す(古いタスクをキャンセルして置き換える)ことで、発火せず完了した
    /// タスクが残って以後の検知を塞ぐことを防ぐ。
    ///
    /// 注: filePath は schedule 時点でキャプチャせず、発火時に再確認する。
    /// handleRename で filePath が更新されると、rename と grace period の競争状態で
    /// 新しいパスが存在する場合、ウィンドウを閉じずに監視を継続するため。
    private func scheduleFileGone() {
        fileGoneTask?.cancel()
        fileGoneTask = Task { @MainActor [weak self, clock, fileGoneGracePeriod] in
            try? await clock.sleep(for: .seconds(fileGoneGracePeriod))
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
