import BefoldKit
import Foundation
import PDFKit

/// PDF 面の文書内検索の状態（TASK-570）。窓ごとに 1 個。
///
/// **面を直接触らない。** ハイライトと移動は `ZoomingPDFView` のメソッドを
/// `PDFViewProxy` 越しに呼ぶ。面への書き込み口を 1 つに保つ約束（TASK-574.1）を、
/// 検索を足すことで割らないため。
///
/// **検索は非同期（`beginFindString`）で行う。** 同期の `findString` は初回に
/// 文書全体のテキスト抽出を行い、実測で 150 ページの PDF に 152.4ms かかった
/// （約 9 フレームぶんのブロック）。非同期版は 0.0ms で戻り、仕事を別スレッドで
/// 進めながら **通知をメインスレッドへ返す**ため、`@MainActor` に閉じたまま扱える
/// （実測: match / end とも `Thread.isMainThread == true`、完了まで 150.8ms）。
/// `PDFDocument` / `PDFView` は非 Sendable なので、この性質が無いと成立しない。
@MainActor
@Observable
final class PDFFindModel {
    /// 検索バーを出しているか。
    private(set) var isOpen = false
    /// 入力中の検索語。
    private(set) var query = ""
    /// いま見つかっている一致。検索の進行に合わせて増える。
    private(set) var matches: [PDFSelection] = []
    /// 選択中の一致の位置（0 始まり）。未選択は -1。
    private(set) var currentIndex = -1
    /// 検索が走行中か。
    private(set) var isSearching = false

    /// 面への橋渡し。**弱参照の口を共有する**（面を所有しない）。
    private let pdfViewProxy: PDFViewProxy
    /// 大文字小文字を区別するか。`FindOptionsPreference` の同名の値をそのまま使う。
    private let caseSensitive: () -> Bool

    /// **走行中の検索の世代。** 購読を外した後に届く通知を捨てるための番号。
    /// これだけでは足りない——下の `matchesCurrentQuery(_:)` の doc を参照。
    private var generation = 0
    /// いま購読している文書。検索の開始時に差し替える。
    private weak var searchingDocument: PDFDocument?
    /// 購読トークンの置き場。**`deinit` から片付けたいので MainActor の外に置く**
    /// （`deinit` は隔離されていないので、`@MainActor` のプロパティは触れない）。
    private let observers = ObserverBox()

    /// 通知の購読トークンを持つだけの箱。`NotificationCenter.removeObserver` は
    /// スレッド安全なので、どのスレッドから片付けてもよい。
    private final class ObserverBox: @unchecked Sendable {
        private let lock = NSLock()
        private var tokens: [NSObjectProtocol] = []

        func append(_ token: NSObjectProtocol) {
            lock.lock(); defer { lock.unlock() }
            tokens.append(token)
        }

        func removeAll() {
            lock.lock()
            let taken = tokens
            tokens = []
            lock.unlock()
            for token in taken {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    init(pdfViewProxy: PDFViewProxy, caseSensitive: @escaping () -> Bool) {
        self.pdfViewProxy = pdfViewProxy
        self.caseSensitive = caseSensitive
    }

    deinit {
        // 検索の途中で窓が閉じた場合に購読を残さない。`[weak self]` を付けてあるので
        // 残っても無害だが、共有の NotificationCenter にトークンを溜めない。
        observers.removeAll()
    }

    /// 件数表示（"3/12"）。書式は web 面と共有の規則（`FindMatchCounter`）。
    /// 検索語が空のあいだは何も出さない（web 面の `updateCount` と同じ振る舞い）。
    var countText: String {
        guard !query.isEmpty else { return "" }
        return FindMatchCounter.text(currentIndex: currentIndex, count: matches.count)
    }

    // MARK: - 開閉

    func open() {
        isOpen = true
    }

    /// 閉じるときはハイライトも消す。残すと、バーを閉じた後も黄色が残り続ける。
    ///
    /// **閉じたらフォーカスを面へ戻す（TASK-579）。** 入力欄が消えた後の first responder は
    /// 宙に浮き、そのままではスペースや矢印で PDF を送れない。戻し先を「いま読んでいる面」に
    /// 決め打つ理由は `PDFViewProxy.focusSurface()` の doc を参照。
    ///
    /// **ここはユーザー操作専用。** 呼び出し元は検索バーの × と Esc だけで、文書の
    /// 差し替えは `documentChanged()` を通る（そちらはフォーカスを動かさない）。
    /// 操作していない契機で面へ移すと、サイドバーを矢印で流し読み中にフォーカスを奪う
    /// （TASK-581 で実際に起きた回帰）。
    func close() {
        isOpen = false
        cancelSearch()
        query = ""
        clearMatches()
        pdfViewProxy.focusSurface()
    }

    // MARK: - 検索

    /// 検索語を差し替えて検索し直す。
    func setQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        restartSearch()
    }

    /// 大文字小文字の区別が変わったときに呼ぶ（設定は窓の外で持つ）。
    func reapplyOptions() {
        guard isOpen, !query.isEmpty else { return }
        restartSearch()
    }

    /// 文書が差し替わったら結果は無効。**`present(...)` の後に呼ぶこと。**
    func documentChanged() {
        cancelSearch()
        clearMatches()
    }

    private func restartSearch() {
        cancelSearch()
        clearMatches()
        guard !query.isEmpty, let document = pdfViewProxy.pdfView?.document else { return }

        generation += 1
        let searchGeneration = generation
        searchingDocument = document
        isSearching = true

        let center = NotificationCenter.default
        // 通知はメインスレッドへ来る（実測）。queue: .main を指定すると、
        // 同期区間の途中で割り込む形が増えるので指定しない。
        observers.append(center.addObserver(
            forName: .PDFDocumentDidFindMatch, object: document, queue: nil
        ) { [weak self] notification in
            // **この通知はメインスレッドで届く**（実測: `Thread.isMainThread == true` を
            // match / end の両方で確認 / TASK-570）。`PDFSelection` は非 Sendable なので
            // 型の上では境界を越えられないが、実際には越えていない——同じスレッドで
            // 受けて同じスレッドで使う。`beginFindString` は PDFKit が自前のキューで
            // 走らせて結果をメインへ返す API で、この性質は PDFKit 側の契約。
            nonisolated(unsafe) let selection = notification
                .userInfo?[Self.foundSelectionKey] as? PDFSelection
            MainActor.assumeIsolated {
                self?.handleMatch(selection, generation: searchGeneration)
            }
        })
        observers.append(center.addObserver(
            forName: .PDFDocumentDidEndFind, object: document, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleEnd(generation: searchGeneration) }
        })

        let options: NSString.CompareOptions = caseSensitive() ? [] : [.caseInsensitive]
        document.beginFindString(query, withOptions: options)
    }

    /// PDFKit が一致を載せる userInfo のキー。SDK の `PDFDocumentFoundSelectionKey`
    /// と同じ文字列（ヘッダ実測）。
    private static let foundSelectionKey = "PDFDocumentFoundSelection"

    /// 一致が 1 件届いた。
    ///
    /// **届いた一致が「いまの検索語のもの」かを内容で確かめる。** 世代番号だけでは
    /// 足りない——`cancelFindString()` は即座には止まらず、通知は文書ごとに飛ぶので、
    /// 同じ文書で検索し直すと**前の検索の一致が新しい購読へ届く**（そのとき世代番号は
    /// 一致してしまう）。番号ではなく中身で判定する。
    private func handleMatch(_ selection: PDFSelection?, generation: Int) {
        guard generation == self.generation else { return }
        guard let selection, matchesCurrentQuery(selection) else { return }
        matches.append(selection)
        // 1 件目が届いた時点で選択して見せる。全件を待つと、大きな文書で
        // 「打ったのに何も起きない」時間が 150ms 続く。
        if currentIndex < 0 {
            currentIndex = 0
            showCurrent()
        } else {
            refreshHighlights()
        }
    }

    /// その一致が現在の検索語のものか。大文字小文字の扱いは検索時のオプションに揃える。
    private func matchesCurrentQuery(_ selection: PDFSelection) -> Bool {
        guard let string = selection.string else { return false }
        return caseSensitive()
            ? string == query
            : string.compare(query, options: .caseInsensitive) == .orderedSame
    }

    private func handleEnd(generation: Int) {
        guard generation == self.generation else { return }
        isSearching = false
        removeObservers()
    }

    private func cancelSearch() {
        if searchingDocument?.isFinding == true { searchingDocument?.cancelFindString() }
        searchingDocument = nil
        isSearching = false
        // 世代を進めることで、これ以降に届く通知はすべて捨てられる。
        generation += 1
        removeObservers()
    }

    private func removeObservers() {
        observers.removeAll()
    }

    private func clearMatches() {
        matches = []
        currentIndex = -1
        pdfViewProxy.pdfView?.clearFindMatches()
    }

    // MARK: - 移動

    /// 次の一致へ。末尾からは先頭へ回る（web 面の `nextMatchIndex` と同じ）。
    func moveToNext() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        showCurrent()
    }

    /// 前の一致へ。先頭からは末尾へ回る。
    func moveToPrevious() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        showCurrent()
    }

    private func showCurrent() {
        guard matches.indices.contains(currentIndex) else { return }
        pdfViewProxy.pdfView?.showFindMatches(matches, current: matches[currentIndex])
    }

    private func refreshHighlights() {
        let current = matches.indices.contains(currentIndex) ? matches[currentIndex] : nil
        pdfViewProxy.pdfView?.showFindMatches(matches, current: current, scroll: false)
    }
}
