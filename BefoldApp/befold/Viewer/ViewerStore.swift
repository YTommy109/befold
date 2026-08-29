import BefoldKit
import Foundation

/// ビューアの表示状態を管理する。
/// ファイルの読み込み・監視・削除検知を行い、UI にバインドされるプロパティを更新する。
/// 読み込み(I/O・デコード)はバックグラウンドで行い、結果だけをメインアクターで適用する。
///
/// 責務ごとに 3 ファイルへ分かれている。このファイルが対象ファイルの保持・表示モード・
/// 生成(init)・close を持ち、`ViewerStore+Loading` が読み込み経路、
/// `ViewerStore+FileWatching` が監視・rename・削除検知を担う。
///
/// 読み込みが確定させた表示状態(content / fileType / filePath / rejectReason など UI が
/// 観測する値)はこの型が持たず、`contentState`(`ViewerContentState`)へ委ねる。
/// 書き換えの入口もそちらに閉じており、ここからも直接は代入できない。
@MainActor
@Observable
final class ViewerStore {
    /// debounceDelay を引数に含めることで、削除確定のグレース期間の導出元
    /// (watcherDebounceDelay)と実際に watcher が使う debounce を型で一致させる
    /// (呼び出し側の「揃える」努力に頼らない)。
    typealias WatcherFactory = @MainActor @Sendable (
        URL,
        TimeInterval,
        @escaping @MainActor @Sendable () -> Void,
        (@MainActor @Sendable (URL) -> Void)?
    ) -> FileWatching

    /// チャンクリーダーの生成(ファイルを開いて先頭をプローブする)はバックグラウンドの
    /// 読み込みタスクから呼ばれるため、メインアクター隔離にしない。
    typealias ChunkedReaderFactory = ViewerLoadPipeline.ChunkedReaderFactory

    /// openFile / handleRename で即時更新する、読み込み対象の URL。バックグラウンド読み込み
    /// (loadContent → performLoad)へ渡すために使い、公開の filePath とは異なりロード完了を待たない。
    /// 公開 filePath は apply() 内で fileType / content と同時にのみ更新する(下記 pendingFileType 参照)。
    @ObservationIgnored private(set) var pendingURL: URL?

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
    /// 呼んでよいのは `ViewerStore+FileWatching` の openFile / handleRename だけ。
    func setPendingURL(_ url: URL) {
        pendingURL = url.nativeBackedFileURL
    }

    /// pendingURL が指す読み込み対象ファイルの種別。openFile / handleRename で pendingURL と
    /// 同時に即時更新する内部値。バックグラウンド読み込み(loadContent → performLoad)へ渡すために使い、
    /// 公開の fileType とは異なりロード完了を待たない。
    /// 公開 fileType は apply() 内で filePath / content と同時にのみ更新する
    /// (filePath だけ先行して変わると、旧ファイルの fileType に新ファイルの filePath が
    /// 組み合わさった中間状態が描画されてしまうため)。
    @ObservationIgnored var pendingFileType: FileType = .mmd

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

    /// git 差分を重ねて表示するモードかどうか。実際に差分が描けるかは `diffContent` にもよる。
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

    /// ソース表示へ重ねる git 差分の取得状態と本文（unified diff）。取得は
    /// `ViewerDiffPresenter` が行い、ここへ結果だけを置く。取得が飛行中の間は
    /// `.pending` で、確定して描ける差分が無ければ `.unavailable`
    /// （表示は通常のソース表示になる）。
    ///
    /// 値は常に「いま開いているファイル」の差分であり、対象が変わる `openFile` で
    /// 捨てる。取得は非同期なので、着地時の URL 一致確認（呼び出し側）だけでは
    /// 切替直後に前のファイルの差分が残る（開始時の無効化と着地時の確認は別物）。
    var diffContent: ViewerDiffContent = .unavailable

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
    /// 差し替えてよいのは `ViewerStore+Loading` の loadContent と close だけ。
    @ObservationIgnored var loadTask: Task<Void, Never>?

    /// 読み込みの世代番号。loadContent が予約されるたびに進み、
    /// 追い越された古い読み込み結果(stale outcome)の適用を防ぐ。
    /// 進めてよいのは `ViewerStore+Loading` の loadContent だけ。
    @ObservationIgnored var loadGeneration = 0

    /// 削除確定のグレース期間を持つ係。張り直しは `ViewerStore+FileWatching` が行う。
    let fileGoneWatchdog: FileGoneWatchdog

    /// 読み込みが確定させた表示状態。窓ごとに 1 つで、生成後は差し替えない
    /// (差し替えると SwiftUI の観測が切れる)。
    let contentState = ViewerContentState()

    /// 監視は `ViewerStore+FileWatching` が張り替え、close がこのファイルで止める。
    var fileWatcher: FileWatching?
    let makeWatcher: WatcherFactory
    /// makeWatcher(openFile 時)へ渡す debounce 間隔。グレース期間の導出元でもある。
    let watcherDebounceDelay: TimeInterval
    let makeChunkedReader: ChunkedReaderFactory
    /// 注入された fileReader。ウィンドウ層(ViewerWindowController)が pathResolver の構築に
    /// 同一インスタンスを共有できるよう、fileExists/isExistingFile 越しだけでなく直接公開する。
    let fileReader: any FileReading
    let contentLoader: ContentLoader

    /// 行番号表示の設定(永続化と CLI の起動限り上書きを含む)。
    let lineNumbersSetting: ShowLineNumbersSetting

    /// 行番号付きコード表示を有効にするかどうか。実体は `lineNumbersSetting` が持つ。
    var showLineNumbers: Bool {
        get { lineNumbersSetting.isEnabled }
        set { lineNumbersSetting.isEnabled = newValue }
    }

    /// 表示中の文書のライブな倍率。**窓が生きている間はこの値が有効**で、ファイル単位の
    /// 保存値(`ZoomStore`)は「次にその文書を開くときの既定値」にすぎない
    /// (ADR 0002「文書の状態の規則」)。保存値を読んでここへ入れるのは、窓がその文書を
    /// 提示し始めるとき(オープン・ファイル切替)だけ。生きている窓が読み直すと、
    /// 他窓の操作が後から効いてしまう。
    var zoom: Double = ZoomStore.defaultZoom

    /// 次にファイル/モードの切替で描画するとき、JS へ渡すスクロール復元位置。
    /// `zoom` と同じ規則で、提示開始(オープン・ファイル切替・モード切替)のときだけ
    /// この窓の記憶(`WindowPresentationMemory`)から入れる。
    var scrollPositionToRestore: Double = 0
    /// PDF の面へ渡す回転角(0 / 90 / 180 / 270)。窓の記憶から読んだライブ値で、
    /// 永続化はしない(`WindowPresentationMemory`)。PDF 以外では常に 0。
    var pdfRotation: Int = 0

    /// コード表示中(ソースモードまたはコード形式ファイル)かどうか。
    /// トップバーの表示可否と行番号メニューの有効判定が共有する。
    var showsCodeContent: Bool {
        if contentState.isRejected { return false }
        if isSourceMode { return true }
        if case .code = contentState.fileType { return true }
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
        lineNumbersSetting = ShowLineNumbersSetting(defaults: defaults)
        makeWatcher = watcherFactory ?? { url, debounceDelay, onChange, onRename in
            FileWatcher(path: url, debounceDelay: debounceDelay, onChange: onChange, onRename: onRename)
        }
        self.watcherDebounceDelay = watcherDebounceDelay
        makeChunkedReader = chunkedReaderFactory ?? ViewerLoadPipeline.defaultChunkedReaderFactory
        self.fileReader = fileReader
        contentLoader = ContentLoader(fileReader: fileReader)
        // グレース期間は watcher の debounce から導出するため、テストで短い debounce を
        // 注入すれば自動的に短縮される(プロダクト既定 0.2s なら従来どおり 1.0s)。
        fileGoneWatchdog = FileGoneWatchdog(clock: clock, gracePeriod: watcherDebounceDelay * 5)
    }

    /// ファイル監視を停止し、リソースを解放する。
    func close() {
        loadTask?.cancel()
        loadTask = nil
        contentState.cancelLoading()
        fileGoneWatchdog.cancel()
        fileWatcher?.stop()
        fileWatcher = nil
    }
}
