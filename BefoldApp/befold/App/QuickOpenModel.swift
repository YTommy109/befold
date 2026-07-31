import BefoldKit
import Foundation

/// Quick Open が外の世界に触れる口。候補源・ファイルシステム・現在の表示位置を
/// プロトコル越しに受けることで、モデルをウィンドウにもパネルにも依存させない。
@MainActor
protocol QuickOpenEnvironment: AnyObject {
    /// 相対パス(`./` `../`)の基準になる、いま開いているファイルのディレクトリ。
    /// ウィンドウが 1 枚も無ければ nil。
    var baseDirectory: URL? { get }
    /// 隠しファイルを出すか。Quick Open は独自設定を持たず `HiddenFilesPreference` に従う。
    var includingHiddenFiles: Bool { get }
    /// fuzzy 検索の候補集合。パネルを開いた時点の索引を使う。
    /// git サブプロセスとディレクトリ再帰走査を伴うため、実装は MainActor を離れて構築する。
    func candidateSet() async -> QuickOpenCandidateSet
    /// ディレクトリ直下のエントリ(隠しファイルを含む全件)。
    /// 応答しないボリュームでは列挙自体が待たされるため、実装は MainActor を離れて行う。
    func directoryEntries(in directory: URL) async -> [URL]
    /// 応答しないボリュームでは stat 自体が待たされるため、実装は MainActor を離れて行う。
    func isDirectory(_ url: URL) async -> Bool
    /// ディレクトリなら中の 1 ファイル、ファイルならそれ自身。開けなければ nil。
    /// ディレクトリ列挙(stat の繰り返し)を伴うため、実装は MainActor を離れて行う。
    func resolveFileToOpen(at url: URL) async -> URL?
}

/// 入力から候補配列を導き、決定を注入されたクロージャへ渡す。
/// パネルの見た目やキーイベントの配線は持たず、判断だけを受け持つ。
@MainActor
@Observable
final class QuickOpenModel {
    /// fuzzy 検索の表示上限。
    private static let fuzzyLimit = 50
    /// 空入力時に出す履歴 + ブックマークの上限。
    private static let historyLimit = 20

    private let environment: any QuickOpenEnvironment
    private let onOpen: (URL) -> Void
    /// パネルを開いた時点で 1 度だけ取る。入力のたびに索引を取り直さない。
    /// 構築は MainActor の外で走るため、到着するまでは空集合で振る舞う。
    private var candidateSet = QuickOpenCandidateSet(candidates: [], isTruncated: false)

    /// 候補集合の取得タスク。init で 1 度だけ起動し、到着後に表示を差し替える。
    private var loadTask: Task<Void, Never>?
    /// 進行中の絞り込みタスク(パスモードのみ非同期)。
    private var refreshTask: Task<Void, Never>?
    /// 絞り込みの世代番号。遅れて返ってきた古い結果を捨てるために使う。
    private var refreshGeneration = 0

    private var storedQueryText = ""

    /// 入力欄の文字列。値が変わるたびに `refresh()` で候補を絞り込み直す。
    /// setter に処理を書く形でも、`@Observable` プロパティに `didSet` を付ける形でも
    /// SwiftUI の `TextField`(`@Bindable` の `$model.queryText`)経由で発火するため
    /// どちらでも動く。ここでは絞り込みの起動点を setter に明示しておく。
    var queryText: String {
        get { storedQueryText }
        set {
            guard newValue != storedQueryText else { return }
            storedQueryText = newValue
            refresh()
        }
    }

    /// いまリストに出す候補。
    private(set) var candidates: [QuickOpenCandidate] = []
    /// リスト内の選択位置。候補が空なら 0。
    private(set) var selectedIndex = 0

    /// 一致なしの表示を出すか。候補ゼロは正常な状態で、アラートは出さない。
    var showsNoMatches: Bool {
        candidates.isEmpty
    }

    /// 候補が上限で打ち切られた旨をリスト末尾に出すか。黙って切り捨てない。
    /// パスモードは親ディレクトリを列挙するだけで上限を持たないため出さない。
    var showsTruncationNotice: Bool {
        candidateSet.isTruncated && !isPathMode
    }

    /// init は同期で完了する。候補集合の構築(git サブプロセス・再帰走査)を待たないため、
    /// パネルは即時表示でき、集合の到着後に候補表示だけが差し替わる。
    init(environment: any QuickOpenEnvironment, onOpen: @escaping (URL) -> Void) {
        self.environment = environment
        self.onOpen = onOpen
        refresh()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let set = await environment.candidateSet()
            guard !Task.isCancelled else { return }
            candidateSet = set
            // 集合の到着時点の入力に対して絞り込み直す。到着までに打たれた文字も反映される。
            refresh()
        }
    }

    /// 進行中の候補読み込み・絞り込みが落ち着くまで待つ。
    /// 非同期化した収集ロジックを決定的に検証するためのシーム。
    func waitForPendingWork() async {
        await loadTask?.value
        await refreshTask?.value
    }

    /// 選択を上下に動かす。両端では止まり、巻き戻らない。
    func moveSelection(by offset: Int) {
        guard !candidates.isEmpty else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + offset, 0), candidates.count - 1)
    }

    /// 選択中の候補を開く。開ける対象が無ければ何もしない。
    func commitSelection() async {
        guard candidates.indices.contains(selectedIndex) else { return }
        guard let target = await environment.resolveFileToOpen(at: candidates[selectedIndex].url) else { return }
        onOpen(target)
    }

    /// パスモードで候補の共通接頭辞まで補完する。
    /// 候補が 1 件だけでそれがディレクトリなら、末尾に `/` を付けて次の階層へ進む。
    /// パスモード以外では何もしない。
    func completePath() async {
        guard case let .path(path) = QuickOpenQuery.classify(queryText),
              let split = PathModeSplit(path: path, baseDirectory: environment.baseDirectory),
              !candidates.isEmpty
        else { return }

        let names = candidates.map(\.url.lastPathComponent)
        guard let completion = commonPrefix(of: names) else { return }

        var completed = split.parentText + completion
        if candidates.count == 1, await environment.isDirectory(candidates[0].url) {
            completed += "/"
        }
        queryText = completed
    }

    /// 現在の入力に対して、候補の `displayPath` 上で強調表示すべき文字インデックス。
    /// fuzzy は一致文字、パスモードは末尾断片に一致するファイル名の先頭を返す。空入力は空。
    func highlightedIndices(in candidate: QuickOpenCandidate) -> [Int] {
        switch QuickOpenQuery.classify(queryText) {
        case .empty:
            []
        case let .fuzzy(query):
            FuzzyMatcher.matchedIndices(query: query, text: candidate.displayPath)
        case let .path(path):
            pathHighlightIndices(path: path, in: candidate)
        }
    }

    /// パスモードの前方一致は「ファイル名の先頭 fragment 文字」に相当する。
    /// displayPath 上でファイル名が始まる位置から、断片の長さぶんを強調位置として返す。
    private func pathHighlightIndices(path: String, in candidate: QuickOpenCandidate) -> [Int] {
        guard let split = PathModeSplit(path: path, baseDirectory: environment.baseDirectory),
              !split.fragment.isEmpty
        else { return [] }
        let name = candidate.url.lastPathComponent
        let nameStart = candidate.displayPath.count - name.count
        guard nameStart >= 0 else { return [] }
        let length = min(split.fragment.count, name.count)
        return Array(nameStart ..< (nameStart + length))
    }

    // MARK: - Private

    private var isPathMode: Bool {
        if case .path = QuickOpenQuery.classify(queryText) { return true }
        return false
    }

    /// 絞り込みの起動点。空入力・fuzzy はメモリ上の候補集合に対する純粋な計算なので同期で確定させ、
    /// ディレクトリ列挙を伴うパスモードだけをタスクに逃がす。遅れて返った古い世代の結果は捨てる。
    private func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = nil

        switch QuickOpenQuery.classify(queryText) {
        case .empty:
            apply(candidateSet.initialCandidates(limit: Self.historyLimit))
        case let .fuzzy(query):
            apply(candidateSet.matches(query: query, limit: Self.fuzzyLimit))
        case let .path(path):
            refreshTask = Task { [weak self] in
                guard let self else { return }
                let result = await pathCandidates(for: path)
                guard !Task.isCancelled, generation == refreshGeneration else { return }
                apply(result)
            }
        }
    }

    private func apply(_ newCandidates: [QuickOpenCandidate]) {
        candidates = newCandidates
        selectedIndex = 0
    }

    /// 親ディレクトリの中身を末尾断片で前方一致(大文字小文字を無視)して絞り込む。
    private func pathCandidates(for path: String) async -> [QuickOpenCandidate] {
        guard let split = PathModeSplit(path: path, baseDirectory: environment.baseDirectory) else { return [] }
        let fragment = split.fragment.lowercased()
        // 断片自体がドット始まりなら、隠しファイルを狙って打っているとみなして出す。
        let includesHidden = environment.includingHiddenFiles || HiddenFileRule.isHidden(component: fragment)

        return await environment.directoryEntries(in: split.parentDirectory)
            .filter { entry in
                let name = entry.lastPathComponent
                guard includesHidden || !HiddenFileRule.isHidden(component: name) else { return false }
                // 空断片(末尾スラッシュ)は絞り込みなしで全件。range(of:"") は nil を返すため明示する。
                return fragment.isEmpty
                    || name.range(of: fragment, options: [.caseInsensitive, .anchored]) != nil
            }
            .map { QuickOpenCandidate(url: $0, displayPath: $0.path, origin: .indexed) }
    }

    /// 大文字小文字を無視した共通接頭辞。表記は最初の候補のものを採る
    /// (打ち直しでケースが揺れないよう、実在するファイル名の綴りに寄せる)。
    /// Foundation の commonPrefix(with:options:) は「大小無視で比較し表記はレシーバ側」を
    /// そのまま実装しており、合成文字・正規化の扱いも標準側に寄せられる。
    private func commonPrefix(of names: [String]) -> String? {
        guard let first = names.first else { return nil }
        return names.dropFirst().reduce(first) {
            $0.commonPrefix(with: $1, options: .caseInsensitive)
        }
    }
}

/// パス入力を「確定した親ディレクトリ」と「未確定の末尾断片」に分ける。
///
/// 分解は文字列の最後の `/` で行い、ファイルシステムには触らない。
/// 親ディレクトリだけを解決対象にすることで、打ちかけの断片が
/// ディレクトリとして解決されてしまうのを防ぐ。
private struct PathModeSplit {
    /// 入力のうち親ディレクトリにあたる部分(末尾の `/` を含む)。補完で前置きに使う。
    let parentText: String
    let parentDirectory: URL
    let fragment: String

    /// 親ディレクトリを解決できない場合は nil。
    init?(path: String, baseDirectory: URL?) {
        // `~` 単独はホームディレクトリの中身を出す意図とみなし、断片なしとして扱う。
        let normalized = path == "~" ? "~/" : path

        if let slashIndex = normalized.lastIndex(of: "/") {
            let boundary = normalized.index(after: slashIndex)
            parentText = String(normalized[..<boundary])
            fragment = String(normalized[boundary...])
        } else {
            // `/` を含まない `.` や `.gitignore` は、開いているファイルのディレクトリを探す。
            parentText = ""
            fragment = normalized
        }

        guard let directory = Self.resolve(directoryText: parentText, baseDirectory: baseDirectory) else {
            return nil
        }
        parentDirectory = directory
    }

    private static func resolve(directoryText: String, baseDirectory: URL?) -> URL? {
        if directoryText.isEmpty { return baseDirectory }
        if directoryText.hasPrefix("~") {
            return URL(fileURLWithPath: NSString(string: directoryText).expandingTildeInPath).standardizedFileURL
        }
        if directoryText.hasPrefix("/") {
            return URL(fileURLWithPath: directoryText).standardizedFileURL
        }
        guard let baseDirectory else { return nil }
        // `relativeTo:` は基準 URL を「ファイル」とみなして最後の構成要素を差し替えてしまうため、
        // 基準ディレクトリに継ぎ足してから正規化する(`./` で 1 段上がってしまうのを防ぐ)。
        return baseDirectory.appendingPathComponent(directoryText).standardizedFileURL
    }
}
