import SwiftUI

/// 一覧が 0 件になった理由。文言の出し分けはこの値だけで決まる。
///
/// 「対応ファイルがありません」は **絞り込みが 1 つも効いていないとき専用** の文言。
/// 絞り込みで消えた場合にこれを出すと、開ける文書で満たされたフォルダーでも
/// 読み込みに失敗したように読める(TASK-287 / TASK-405)。
enum SidebarEmptyReason: Equatable {
    /// 列挙自体に失敗した(権限が無い・消えた)。**空だったのではない**ので、
    /// 絞り込みのどの理由よりも先に確定させる(TASK-410)。
    case enumerationFailed
    /// 絞り込みは効いていない。このフォルダーに開けるファイルが無い。
    case noSupportedFiles
    /// 「変更のみ表示」で消えた。
    case gitChangeFilter
    /// 名前フィルターで消えた。
    case nameFilter
    /// 両方効いている。片方だけを挙げると、解除しても一覧が戻らず
    /// 「解除したのに変わらない」になる。
    case gitChangeAndNameFilter

    /// 見出しの文言キー。
    ///
    /// キーの対応をここに置くのは、View を起動せずに検証できるようにするため。
    /// `body` の switch 内に書くと、理由の判定だけがテストされ、**その理由に
    /// どの文言を割り当てたか**は誰も確かめないまま残る(TASK-405)。
    var titleKey: String.LocalizationValue {
        switch self {
        // ツリー展開の失敗行(FileListEntryRow の help)と同じキーを使う。同じ事象に
        // 2 つの言い回しを作ると、片方だけ直されて画面ごとに説明が食い違う。
        case .enumerationFailed: "folder.enumerationFailed"
        case .noSupportedFiles: "sidebar.empty"
        case .gitChangeFilter: "sidebar.empty.changedFilesOnly"
        case .nameFilter: "sidebar.empty.nameFilter"
        case .gitChangeAndNameFilter: "sidebar.empty.bothFilters"
        }
    }

    /// 説明の文言キー。`nil` は「フォルダー名を代わりに添える」の意味。
    ///
    /// 見出しキーから `.description` を文字列連結で組み立てない。
    /// `String.LocalizationValue` への補間は書式指定子になり、キーとして解決されない。
    var descriptionKey: String.LocalizationValue? {
        switch self {
        case .enumerationFailed: "folder.enumerationFailed.description"
        case .noSupportedFiles: nil
        case .gitChangeFilter: "sidebar.empty.changedFilesOnly.description"
        case .nameFilter: "sidebar.empty.nameFilter.description"
        case .gitChangeAndNameFilter: "sidebar.empty.bothFilters.description"
        }
    }

    /// 添えるシンボル。絞り込みの種類が、対応するツールバーボタンと同じ絵で分かるようにする。
    var systemImage: String {
        switch self {
        // 失敗はツリーの行(FileListEntryRow)と同じ絵にする。
        case .enumerationFailed: "exclamationmark.triangle"
        case .noSupportedFiles: "doc.questionmark"
        case .gitChangeFilter: "arrow.triangle.branch"
        case .nameFilter, .gitChangeAndNameFilter: "line.3.horizontal.decrease.circle"
        }
    }
}

/// 一覧が空のときの案内。サイドバー(FileListView)とプレビュー内フォルダー一覧
/// (FolderListingView)が **同じ 1 つの実装** を使う。
///
/// 空になった理由で文言を変えるのが要点。絞り込みで消えたときに
/// 「対応ファイルがありません」と出すと、開ける文書で満たされたフォルダーでも
/// 読み込みに失敗したように読める(TASK-287)。絞り込みが効いていること自体を伝え、
/// 解除すれば見えると分かる文言にする。
///
/// 2 箇所に同じ出し分けを書き分けない。以前はサイドバーだけが理由で出し分け、
/// プレビュー側は「対応ファイルがありません」固定だった。git 絞り込みが
/// リポジトリ配下のどの階層にも効くようになった時点で(TASK-361.2)、
/// プレビューでも絞り込みによる空が起こるようになり、片側だけ直すと
/// TASK-320 と同型の取り残しになる。
///
/// 同じ理由から、**絞り込みの値にデフォルト引数を付けない**。付けると呼び出し元での
/// 渡し忘れがコンパイルエラーにならず、片側だけ古い出し分けのまま静かに残る。
struct SidebarEmptyState: View {
    /// 文言を決めるのに要る入力一式。
    let context: SidebarEmptyContext

    /// 空になった理由。View を起動せずに検証できるよう純粋関数として切り出す。
    /// 分岐の判断はここだけが持ち、`body` は文言を選ぶだけにする。
    ///
    /// **列挙失敗を最優先で確定する。** 読めなかったフォルダーは絞り込みの結果として
    /// 空になったのではないため、絞り込みの文言(「解除すれば見えます」)を出すと
    /// 解除しても何も起きない案内になる(TASK-410)。順序は
    /// `SidebarDisclosure.state` が失敗を最優先で確定するのと同じ規則。
    /// **一覧がまだ届いていない間は `nil`(＝何も言わない)。** ウィンドウは一覧を空で作って
    /// 非同期に埋めるため(ViewerWindowAssembler)、届く前に `entries.isEmpty` だけで
    /// 判定すると「対応ファイルがありません」が一瞬出てから一覧に置き換わる。
    /// 「変更のみ表示」が ON のときは git status の完了まで待つぶん、この誤った空表示が
    /// 目に見えて長くなる(TASK-530)。プレビュー側(FolderListingView)は未到着を nil で
    /// 表す形で既に同じ区別を実装しており、サイドバーだけがこの非対称を持っていた。
    static func reason(for context: SidebarEmptyContext) -> SidebarEmptyReason? {
        guard context.hasLoadedEntries else { return nil }
        guard !context.didFailEnumeration else { return .enumerationFailed }
        return switch (context.activeGitChangeFilter != nil, context.filterText.isEmpty) {
        case (true, false): .gitChangeAndNameFilter
        case (true, true): .gitChangeFilter
        case (false, false): .nameFilter
        case (false, true): .noSupportedFiles
        }
    }

    /// 文言の割り当ては `SidebarEmptyReason` が持つ。ここで分岐を書き足さない。
    var body: some View {
        if let reason = Self.reason(for: context) {
            ContentUnavailableView(
                String(localized: reason.titleKey, bundle: .l10n),
                systemImage: reason.systemImage,
                description: Text(descriptionText(for: reason))
            )
        }
    }

    /// 説明文。絞り込みで空になったときは解除の案内、そうでなければフォルダー名を添える。
    private func descriptionText(for reason: SidebarEmptyReason) -> String {
        guard let key = reason.descriptionKey else { return context.directoryName }
        return String(localized: key, bundle: .l10n)
    }
}

/// 空状態の文言を決めるのに要る入力一式。呼び出し元(FileListView / FolderListingView)が
/// 引数を個別に並べる代わりに、この 1 値で渡す。
///
/// **値をまとめる目的は、増えたときに片側の呼び出し元だけが古い形で残るのを防ぐこと。**
/// 引数を並べる形だと、新しい入力(列挙失敗)を足したときに片方へ渡し忘れても
/// デフォルト引数さえあればコンパイルが通ってしまう(TASK-320 と同型の取り残し)。
struct SidebarEmptyContext: Equatable {
    /// いま効いている git 絞り込み。nil なら「変更のみ表示」では消えていない。
    let activeGitChangeFilter: SidebarGitStatus?
    /// いま効いている名前フィルターの検索文字列。空なら名前では消えていない。
    /// 判定は `FileListFilter.apply(to:in:)` と同じ「空文字かどうか」で揃える。
    let filterText: String
    /// 「対応ファイルが無い」ほうの文言に添えるフォルダー名。
    let directoryName: String
    /// 一覧の列挙自体に失敗したか。空だったのか読めなかったのかを分ける(TASK-410)。
    let didFailEnumeration: Bool
    /// 一覧が一度でも届いたか。false は「空だった」ではなく「まだ答えが出ていない」。
    /// 空状態の文言はここが true のときだけ出す(TASK-530)。
    let hasLoadedEntries: Bool
}

@MainActor
extension SidebarEmptyContext {
    /// サイドバー(FileListView)の空状態。model の値の組み合わせ方をここ 1 箇所に閉じる。
    ///
    /// 絞り込みの突き合わせ先は `currentDirectory` ではなく **`entriesDirectory`**。
    /// 移動要求は currentDirectory を先に進めるため、一覧が届くまでの間 currentDirectory と
    /// 手元の一覧は別のディレクトリを指す。currentDirectory で突き合わせると、その間だけ
    /// 「状態が別ディレクトリのもの」と判定されて絞り込みが外れ、「絞り込みで空」と
    /// 「対応ファイルなし」が入れ替わる(TASK-285 / TASK-293)。
    init(model: FileListModel) {
        self.init(
            activeGitChangeFilter: model.listFilter.gitChangeFilter(for: model.entriesDirectory),
            filterText: model.filterText,
            directoryName: model.currentDirectory.lastPathComponent,
            didFailEnumeration: model.didFailListing,
            hasLoadedEntries: model.hasLoadedEntries
        )
    }
}
