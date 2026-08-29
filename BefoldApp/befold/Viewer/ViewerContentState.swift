import BefoldKit
import Foundation

/// 読み込みが確定させた表示状態の単一情報源。
///
/// 「いま何を表示しているか」(content / fileType / filePath / rejectReason / 段階読み込みの
/// 進行状況)だけを持ち、どのファイルを見るか(pendingURL・監視)や表示モード・倍率といった
/// 窓側の設定は持たない。それらは `ViewerStore` に残る。
///
/// stored property はすべてこのファイル内で `private(set)` にし、書き換えは下の
/// 「表示状態の書き換え」節にある internal メソッド経由でのみ行う(Swift の private が
/// ファイルスコープであることを使い、`ViewerStore` 側からの直接代入を構造的に塞ぐ)。
/// 呼んでよいのは `ViewerStore+Loading` の読み込み経路と、`ViewerStore.close()` だけ。
///
/// 窓ごとに 1 つで、`ViewerStore` が init で生成して `let` で保持する(差し替えない)。
/// 注入用のデフォルト引数を設けないのは、渡し忘れで別インスタンスが生まれる事故を
/// 起こさないため(`.claude/CLAUDE.md`「決めたことには、破れたら落ちるものを付ける」)。
@MainActor
@Observable
final class ViewerContentState {
    private(set) var content: String = ""
    /// PDF の生データ。`fileType == .pdf` で読み込みに成功したときだけ non-nil。
    /// PDF は `content`(文字列)を持たず、この Data を `PDFView` が描く。
    ///
    /// `PDFPreviewView` が filePath からディスクを読み直す形にしないのは、そちらだと
    /// 「読み込み開始時の無効化」も「着地時の一致確認」も無い経路になり、切替中の
    /// 一瞬に別ファイルを描けてしまうため。表示状態が確定させた content と同じ組で運ぶ。
    private(set) var data: Data?
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
    /// 読み込み完了(apply)で false にリセットする。
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

    /// 段階読み込み中の行チャンクセッション。ファイル再読込・close でリセットする。
    private(set) var chunkSession: (any ChunkedTextReading)?

    /// 前回適用したキャッシュの dataHash。同一内容スキップの比較に使う。
    @ObservationIgnored private var contentHash: Int?

    /// 蓄積済み content に含まれる改行の数(displayedLineCount の増分計算用)。
    @ObservationIgnored private var newlineCount: Int = 0

    /// 開いたファイルが非対応と判定されているかどうか。
    var isRejected: Bool {
        rejectReason != nil
    }

    /// 読み込み中のスピナーを出すか。
    ///
    /// **「まだ何も出せていない」ときだけ出す。** `content` が空でも、PDF の面が
    /// 前の文書を出し続けている区間がある（面の宛先は描画が確定した種別で切り替わる
    /// ので、次の文書が着地するまで PDF が見えている）。PDF は `content` ではなく
    /// `data` で描くため、PDF から離れるときだけ「空」の判定が真になり、
    /// **見えている PDF の上にスピナーが重なって一瞬ちらつく**（TASK-567 の実測）。
    ///
    /// - Parameter isShowingPDFSurface: いま PDF の面を見せているか（`showsPDF`）。
    func showsLoadingIndicator(isShowingPDFSurface: Bool) -> Bool {
        isLoading && content.isEmpty && !isShowingPDFSurface
    }

    // MARK: - 表示状態の書き換え(状態の単一情報源)

    /// 読み込みの開始を反映する(loadContent から)。
    func beginLoading() {
        isLoading = true
    }

    /// 読み込みの着地を反映する(apply から)。
    func finishLoading(url: URL) {
        isLoading = false
        filePath = url
    }

    /// 段階読み込みで取得したチャンクを追記する(loadMoreLines から)。
    /// content / contentRevision / isTruncated / 行数カウンタを一括で進める唯一の入口。
    func appendChunk(_ text: String, isAtEnd: Bool) {
        content += text
        contentRevision += 1
        isTruncated = !isAtEnd
        newlineCount += text.utf8.count(where: { $0 == 0x0A })
        updateDisplayedLineCount()
    }

    /// チャンク読込がエラーで打ち切られたことを反映する(loadMoreLines から)。
    /// isTruncated は true のまま維持する: 正常な EOF(バナーを消す)とエラー打ち切り
    /// (バナーをエラー表示に切り替える)を loadFailed だけで判別させるため。
    func markChunkLoadFailed() {
        chunkSession = nil
        loadFailed = true
    }

    /// 読み込みを打ち切った状態へ戻す(`ViewerStore.close()` から)。
    /// 表示済みの content は残す(閉じる際に画面を空にしない)。
    func cancelLoading() {
        isLoading = false
        chunkSession = nil
    }

    /// 蓄積済み content の改行数から表示行数を再計算する。数え方の規則は
    /// DisplayedLineCount(1 回描画ホストと共有する単一情報源)に委ねる。
    private func updateDisplayedLineCount() {
        displayedLineCount = DisplayedLineCount.count(newlines: newlineCount, in: content)
    }

    /// apply() が一括適用する表示状態の組。読み込み結果の種別(.chunked / .full)ごとに
    /// 値を詰め替えるだけにして、フィールドを増やしたときに片方の分岐だけ更新し忘れる
    /// 事故を構造的に防ぐ。組み立ては `ViewerStore+Loading` の apply が行う。
    struct DisplayState {
        let fileType: FileType
        /// 同一内容スキップの比較に使う dataHash。全文読込でキャッシュがない場合は nil。
        let contentHash: Int?
        let chunkSession: (any ChunkedTextReading)?
        let rejectReason: RejectReason?
        let isTruncated: Bool
        let content: String
        /// PDF の生データ。PDF 以外は常に nil。
        let data: Data?
        /// content から行数カウンタを追従させるかどうか。段階読み込み(.chunked)は
        /// バナー表示に行数を使うため true、全文読込は行数を表示しないため false
        /// (カウンタは 0 にリセットされる)。
        let tracksLineCount: Bool
        /// HTML の charset 宣言有無。.chunked(HTML は非対応)は常に nil。
        let hasDeclaredHTMLCharset: Bool?
    }

    /// 同一内容の再読込かどうか。dataHash・fileType が一致し、直前のチャンク読込も
    /// 失敗していない場合だけ true(キャッシュが無い読み込みは常に false)。
    private func isUnchanged(_ state: DisplayState) -> Bool {
        guard let newHash = state.contentHash else { return false }
        return newHash == contentHash && state.fileType == fileType && !loadFailed
    }

    /// 表示状態を一括更新する。同一内容(dataHash・fileType が一致し、直前のチャンク読込も
    /// 失敗していない)の再読込では何も書き換えず false を返す。
    /// 表示状態のタプルを書き換えるのはこのメソッドだけにする。
    /// 呼んでよいのは `ViewerStore+Loading` の apply。
    func applyDisplayState(_ state: DisplayState) -> Bool {
        if isUnchanged(state) { return false }
        fileType = state.fileType
        contentHash = state.contentHash
        chunkSession = state.chunkSession
        rejectReason = state.rejectReason
        isTruncated = state.isTruncated
        loadFailed = false
        content = state.content
        data = state.data
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
}

/// 読み込み結果から表示状態の組を作る写し。struct 本体に置くと
/// メンバワイズ init が消えるため extension に置く。
extension ViewerContentState.DisplayState {
    /// 読み込み結果(`ViewerLoadPipeline.Outcome`)を表示状態の組へ写す。
    ///
    /// **種別ごとの差はこの写しだけに閉じる。** 実際の書き換えは
    /// `applyDisplayState` に一本化してあるので、読み込み経路が増えても
    /// 書き換え側は変わらない。写しを `ViewerStore` 側に置かないのは、
    /// `Outcome` に case が増えるたびに網羅的 switch の受け手として
    /// `ViewerStore` グループが太るため(TASK-564.6。PDF の Data 経路が
    /// TASK-564.1 でここへ足される)。
    ///
    /// - Returns: 提示すべき表示状態が無いとき(`.missing`)は nil。
    ///   ファイル消失の扱いは表示状態ではなく窓の判断なので、呼び出し側が負う。
    init?(outcome: ViewerLoadPipeline.Outcome, fileType: FileType) {
        switch outcome {
        case .missing:
            return nil
        case let .chunked(session, cache, firstChunk, isAtEnd):
            self.init(
                fileType: fileType,
                contentHash: cache.dataHash,
                chunkSession: session,
                rejectReason: nil,
                isTruncated: !isAtEnd,
                content: firstChunk,
                data: nil,
                tracksLineCount: true,
                hasDeclaredHTMLCharset: nil
            )
        case let .binary(loaded):
            // PDF の生データ経路。content は空のままで、描くのは PDFView(`data`)。
            // 拒否理由の扱いと hash の規則は .full と同じ。
            self.init(
                fileType: fileType,
                contentHash: loaded.contentHash,
                chunkSession: nil,
                rejectReason: loaded.rejectReason,
                isTruncated: false,
                content: "",
                data: loaded.data,
                tracksLineCount: false,
                hasDeclaredHTMLCharset: nil
            )
        case let .full(loaded, cache):
            self.init(
                fileType: fileType,
                // テキストは NormalizedTextCache、バイナリは LoadedContent が hash を運ぶ。
                // どちらも「読み込みに成功したときだけ non-nil」という同じ規則に従う。
                contentHash: cache?.dataHash ?? loaded.contentHash,
                chunkSession: nil,
                rejectReason: loaded.rejectReason,
                isTruncated: false,
                content: loaded.content,
                data: nil,
                tracksLineCount: false,
                hasDeclaredHTMLCharset: loaded.hasDeclaredHTMLCharset
            )
        }
    }
}
