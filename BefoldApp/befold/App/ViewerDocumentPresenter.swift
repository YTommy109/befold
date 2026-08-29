import BefoldKit
import Foundation

/// **窓がその文書をどう提示しているか**——表示モード・倍率・スクロール位置——の遷移を受け持つ。
///
/// ADR 0002「文書の状態の規則」1 の実装点であり、次の 2 つの不変条件をここに閉じている。
///
/// 1. **保存値を読むのは提示開始の 3 契機だけ**（オープン・ファイル切替・モード切替）。
///    生きている窓が読み直すと、他窓の操作が後から効く。
/// 2. **表示中ファイル・表示モードを書き換える前に、退場側のスクロール位置を確定保存する**
///    （save-before-mutate）。後で保存すると入場側のキーへ誤って書かれる。
///
/// 1 の呼び出し元は `ViewerWindowPresentationEntryPointTests` がソース走査で個数を
/// 固定している（契機を増やす変更はテストが落ちる）。
///
/// ウィンドウ側への問い合わせはクロージャで受ける（`WebViewCommandController` と同じ形）。
/// プロトコルにすると、ウィンドウコントローラが兼ねる準拠がもう 1 つ増える。
@MainActor
final class ViewerDocumentPresenter {
    /// 表示状態の唯一の真実の源。
    private let store: ViewerStore
    /// ファイル毎の永続表示状態（倍率・サイドバー開閉・ウィンドウフレーム）。全ウィンドウ共有。
    private let perFileState: PerFileStateStore
    /// この窓の生存期間だけのファイル単位の記憶（スクロール位置・表示モード）。
    /// **窓ごとに 1 個をここが所有する。** 外から注入しないのは、共有インスタンスを
    /// 渡す経路をそもそも作らないため（`WindowPresentationMemory` の doc 参照）。
    /// 読み書きするのはこの型だけ。`private` にしていないのは、テストが記憶の中身を
    /// 観測するためだけの妥協（本番コードからここを触らないこと）。
    let presentationMemory = WindowPresentationMemory()
    /// スクロール位置の確定保存の実行先（JS ラウンドトリップを挟む）。
    private let webViewCommands: WebViewCommandController
    /// 提示中のファイル。切替・リネームで変化するため都度参照する（窓と同じ共有参照）。
    private let currentDocument: CurrentDocumentRef
    /// そのモードをいま選べるか（ADR 0002 段 2 の導出はウィンドウ側に置いたまま引く）。
    private let canSelect: (ViewerDisplayMode) -> Bool
    /// ツールバーの再同期。
    private let refreshToolbar: () -> Void
    /// 表示モードが変わったときの差分の取り直し。
    private let refreshDiff: () -> Void

    /// cmd+U でソース系モードを離れた直前の「どのソース系モードだったか」と、その時のファイル。
    /// レンダリング表示中しか値を持たない（ソース系モードへ入った時点で setDisplayMode が捨てる）。
    /// 保存値からは復元できない: 離脱側の cmd+U が保存値を `.rendered` で上書きするため、
    /// 戻る側が保存値を読むと必ず `.source` に落ちる（TASK-370）。
    /// 記憶するのは `toggleSourceView()`、捨てるのは `setDisplayMode(_:)`。この 2 つに閉じる。
    private var sourceToggleReturn: (pathKey: String, mode: ViewerDisplayMode)?

    init(
        store: ViewerStore,
        perFileState: PerFileStateStore,
        webViewCommands: WebViewCommandController,
        currentDocument: CurrentDocumentRef,
        canSelect: @escaping (ViewerDisplayMode) -> Bool,
        refreshToolbar: @escaping () -> Void,
        refreshDiff: @escaping () -> Void
    ) {
        self.store = store
        self.perFileState = perFileState
        self.webViewCommands = webViewCommands
        self.currentDocument = currentDocument
        self.canSelect = canSelect
        self.refreshToolbar = refreshToolbar
        self.refreshDiff = refreshDiff
    }

    /// 表示中ファイル・表示モードを書き換える前に、退場側（現在の URL・現在のモード）の
    /// スクロール位置を明示的なキーで確定保存する。
    ///
    /// 切替後に保存すると、退場側の位置が入場側ファイル・入場側モードのキーへ誤って
    /// 保存されるため、必ず書き換え前に呼ぶこと。この save-before-mutate の順序制約を
    /// 負う入口はここだけで、呼び出し点はファイル切替（performFileSwitch）と
    /// モード切替（setDisplayMode）の 2 つ。
    func saveScrollPositionBeforeTransition() {
        webViewCommands.saveCurrentScrollPosition(
            for: currentDocument.url, mode: ViewerBridge.ViewMode(isSourceMode: store.isSourceMode)
        )
    }

    /// **窓がその文書を提示し始めるとき**に、ファイル単位の保存値・記憶をこの窓のライブ値へ読み込む。
    /// 呼んでよいのはオープン（init）とファイル切替（performFileSwitch）だけ
    /// （ADR 0002「文書の状態の規則」1）。生きている窓が再ロードのついでにここを通ると、
    /// 他窓が保存した倍率・位置を拾って勝手に動く（TASK-388）。リネームでも呼ばない
    /// （引き継ぐのは保存値ではなくライブ値。表示モードが同じ理由で読まない = TASK-369）。
    /// スクロール位置のキーは(パス, モード)粒度なので、表示モード確定後に呼ぶこと。
    func beginPresentingDocument(at url: URL) {
        store.zoom = perFileState.zoom.zoom(for: url)
        store.scrollPositionToRestore = restoredScrollPosition(for: url, isSourceMode: store.isSourceMode)
    }

    /// 退場側で発行したスクロール位置の保存が完了したときに、その位置をキーごと記憶し、
    /// キーがいま提示中の文書・モードと一致していればライブな復元値へも追いつかせる。
    ///
    /// **記憶は一致判定の前に行う。** ここへ届くのは退場側（いま提示中とは限らない文書）の
    /// 位置であり、一致したときだけ記憶する形にすると切替の退場側の位置が落ちる。
    ///
    /// 位置の取得は JS のラウンドトリップを挟むため、A→B→A のような素早い往復では
    /// 「A の保存が完了する前に A の提示開始（保存値の同期読み取り）が走る」順序が起きる。
    /// このとき復元値は A の古い位置のままで、遅れて完了した保存が拾い直されることもない
    /// （提示開始の契機は 3 つしかない = TASK-394）。
    ///
    /// **記憶から読み直さず、いま届いた値そのものを使うこと。** ここで反映するのは
    /// 自窓が発行した保存の結果に限られる。
    func applySavedScrollPositionToLiveValue(
        _ position: Double, for url: URL, mode: ViewerBridge.ViewMode
    ) {
        recordScrollPosition(position, for: url, mode: mode)
        guard url.normalizedPathKey == currentDocument.url.normalizedPathKey else { return }
        guard mode == ViewerBridge.ViewMode(isSourceMode: store.isSourceMode) else { return }
        store.scrollPositionToRestore = position
    }

    /// 指定したファイル・モードの記憶済みスクロール位置。提示開始の 3 契機からだけ引く。
    private func restoredScrollPosition(for url: URL, isSourceMode: Bool) -> Double {
        presentationMemory.scrollPosition(
            for: url, mode: ViewerBridge.ViewMode(isSourceMode: isSourceMode)
        )
    }

    /// 面の中で完結した倍率変更(JS のズーム / PDF のピンチ・Ctrl+ホイール)を、
    /// **その倍率が属する文書**のキーで受ける。受け口をここ 1 箇所にするのは、
    /// 面ごとに「ライブ値をいつ更新するか」の規則が分かれると片方だけ直るため。
    ///
    /// ライブ値は「いまこの窓が出している文書」の倍率なので、出所が現在の文書と違う
    /// 遅延通知(切替直後に届いた切替前の文書の通知)では更新しない。保存だけを
    /// 出所のキーへ行う(TASK-391 と同じ作法)。
    func recordZoomChange(_ zoom: Double, for url: URL) {
        if url.normalizedPathKey == currentDocument.url.normalizedPathKey {
            store.zoom = zoom
        }
        perFileState.zoom.setZoom(zoom, for: url)
    }

    /// 描画側から上がってきたスクロール位置を、その位置が属する文書・モードのキーへ記録する。
    /// 通知は遅れて届きうるので、キーは現在の提示対象ではなく通知が載せてきたものを使う
    /// （`ViewerWindowController+Renderer` の doc / TASK-400）。
    func recordScrollPosition(_ position: Double, for url: URL, mode: ViewerBridge.ViewMode) {
        presentationMemory.setScrollPosition(position, for: url, mode: mode)
    }

    /// ファイルの rename / move に伴い、この窓の記憶を新パスへ引き継ぐ。
    /// 永続側（倍率・サイドバー・フレーム）の引き継ぎは `PerFileStateStore.migrate` が行う。
    func migratePresentationMemory(from oldURL: URL, to newURL: URL) {
        presentationMemory.migrate(from: oldURL, to: newURL)
    }

    /// いま表示中のモードを、その種別で成立するモードまで降格して返す。
    /// リネーム追随（`+FileNavigation.handleRename`）が引く。
    func supportedDisplayMode(_ mode: ViewerDisplayMode, for url: URL) -> ViewerDisplayMode {
        mode.supported(for: url)
    }

    /// 記憶済みの表示モードを降格して返す。ファイル切替（`+FileNavigation`）が引く。
    func restoredDisplayMode(for url: URL) -> ViewerDisplayMode {
        presentationMemory.restoredDisplayMode(for: url)
    }

    /// 表示モードを変更し、store・この窓の記憶・ツールバーの表示更新までを一貫して行う。
    /// ツールバーのモード切替セグメントからも View メニューの ⌘1〜⌘3 からも呼ばれる。
    /// 表示モードを変える入口はここだけ。
    func setDisplayMode(_ newValue: ViewerDisplayMode) {
        // validate を通らない経路（ツールバーのセグメント・オーバーフローメニュー）も
        // ここへ来るため、能力の確認は実行側にも置く（ADR 0002）。
        let url = currentDocument.url
        guard canSelect(newValue) else { return }
        // 比較対象は記憶値（displayMode）ではなく、いま実際に出しているモード
        // （effectiveDisplayMode）。プレビューを持たない種別（.code）は保存値が .rendered の
        // ままソースを出しているため、保存値と比べると「選択済みの source セグメント」への
        // クリック・⌘2 が遷移扱いになる。スクロール位置を
        // rendered キーへ退避したまま空の source キーから復元するので先頭へ飛び、
        // 意味の無い .source が記憶される（TASK-368）。
        guard newValue != store.effectiveDisplayMode else { return }
        // ソース系モードへ入った時点で、cmd+U の戻り先の記憶は役目を終える。残しておくと
        // 「diff → cmd+U → cmd+2(source) → cmd+U → cmd+U」で diff へ戻ってしまう。
        if newValue.isSourceMode { sourceToggleReturn = nil }
        saveScrollPositionBeforeTransition()
        applyDisplayMode(newValue)
        // 提示開始（モード切替）。切替先モードのキーから復元位置を読む。ここも保存値を読んで
        // よい 3 契機のひとつ（ADR 0002「文書の状態の規則」1）。
        store.scrollPositionToRestore = restoredScrollPosition(for: url, isSourceMode: store.isSourceMode)
        presentationMemory.setDisplayMode(store.displayMode, for: url)
        // 差分を取れるかどうかは表示モードに依存する。レンダリング表示中の refreshDiff は
        // 差分を捨てるため、モードが変わった契機で取り直さないとソース表示へ切り替えても
        // 差分が出ない（TASK-337）。applyDisplayMode ではなくここに置くのは、モードだけが
        // 変わる呼び出し元が setDisplayMode だけだから（performFileSwitch は URL 更新前に
        // 呼ぶため、そちらへ置くと切替前ファイルに対して git を起こす）。
        refreshDiff()
        // 他ウィンドウへは通知しない（理由は ViewerWindowControllerDelegate の doc / TASK-388）。
    }

    /// 表示モードを変更し、store への反映とツールバーの表示更新までを一貫して行う。
    /// 永続化を伴わない復元（init・performFileSwitch・handleRename）は
    /// 保存値を書き換えないためこちらを使う。
    /// store.displayMode の変更が SwiftUI の更新サイクルをトリガーし、
    /// ViewerWebView.updateNSView → updateContent が呼ばれ、
    /// 自動的にモード切替（必要なら再描画）が行われる。
    ///
    /// 差分表示から離れるときは、取得済みの差分本文をここで捨てる。着地時の確認
    /// （refreshDiff の URL・モード一致）だけでは、遅れて届く結果とは別に
    /// 「既に store に載っている古い本文」が次に差分へ戻った瞬間に一瞬見える。
    func applyDisplayMode(_ newValue: ViewerDisplayMode) {
        if store.displayMode != newValue {
            store.displayMode = newValue
            if !newValue.showsDiff {
                store.diffContent = .unavailable
            }
        }
        refreshToolbar()
    }

    /// CLI の `--source` / `--preview` を適用する。オープン時（init）と、既に開いている
    /// ウィンドウを指定して開き直したときの両方がここを通る唯一の入口。
    ///
    /// 保存値は書き換えない（この起動限りの上書き。ADR 0002「永続化規則」）。
    /// その種別で成立しないモードは降格規則へ通す。降格を挟まないと、ソース表示を持たない
    /// 画像・PDF に `--source` を渡したときだけ規則の外側に出る。
    func applyCLIDisplayMode(isSourceMode: Bool) {
        let url = currentDocument.url
        let requested: ViewerDisplayMode = isSourceMode ? .source : .rendered
        applyDisplayMode(requested.supported(for: url))
    }

    /// 記憶済みのソース表示モードを復元する（記憶は書き換えない）。
    func applyRestoredDisplayMode(for url: URL) {
        applyDisplayMode(presentationMemory.restoredDisplayMode(for: url))
    }

    /// cmd+U のソース表示トグル。レンダリング表示とソース表示を往復する。
    /// ⌘1〜⌘3 の「指定」に対し、こちらは「往復」で動作が違う。
    /// 記憶（sourceToggleReturn）と消費がこのメソッドに閉じるため、
    /// 他の入口（⌘1〜⌘3・ツールバー）は関与しない。
    func toggleSourceView() {
        guard store.isSourceMode else {
            setDisplayMode(sourceToggleTarget)
            return
        }
        // 離れる直前のソース系モードを覚えてからレンダリングへ移る。
        sourceToggleReturn = (currentDocument.url.normalizedPathKey, store.effectiveDisplayMode)
        setDisplayMode(.rendered)
    }

    /// cmd+U でレンダリング表示から戻る先。直前に cmd+U で離れた同じファイルなら
    /// そのモード（差分表示なら差分）、それ以外・選べなくなっている場合は `.source`。
    var sourceToggleTarget: ViewerDisplayMode {
        guard let last = sourceToggleReturn,
              last.pathKey == currentDocument.url.normalizedPathKey, canSelect(last.mode)
        else { return .source }
        return last.mode
    }
}
