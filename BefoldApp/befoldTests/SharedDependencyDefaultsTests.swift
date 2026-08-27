import Foundation
import Testing

/// アプリ全体で 1 つの共有物を受け取る init 引数に、既定値が復活していないことを
/// **宣言のソースを読んで**検証する(TASK-558)。
///
/// この規則はもともと `AppStores` と `DiffDisplayPreference` の doc コメントに
/// 書かれていたが、それだけでは守られなかった——`codeFontPreference` ほか 5 つの
/// 引数に `= CodeFontPreference()` 形の既定値が残り、渡し忘れがコンパイルエラーに
/// ならない状態が続いていた(TASK-319 と同型)。破れたら落ちるものをここに置く。
///
/// 見るのは「型名と同じ型の新しいインスタンスを既定値にしている」形だけ。
/// `fileReader: any FileReading = DefaultFileReader()` のような**実装の選択**は
/// 別物なので対象にしない(共有インスタンスの受け渡しではない)。
@Suite
struct SharedDependencyDefaultsTests {
    /// 検査対象。窓の生成経路で共有物を配っている 2 つの型。
    private static let sources = [
        "befold/App/ViewerWindowManager.swift",
        "befold/App/ViewerWindowController.swift",
    ]

    /// 既定値を残してよい引数と、その理由。**共有インスタンスの受け渡しではないもの**に限る。
    /// ここへ足すときは理由を書くこと(理由の書けないものは既定値を外す側が正しい)。
    private static let allowed: [String: String] = [
        // 既定の GitStatusStore() は「git 状態を持たない縮退状態」を表す。
        // gitFileIndex の既定が DisabledGitFileIndex なのと同じで、共有インスタンスを
        // 渡し忘れた結果として別インスタンスになる形ではない。
        "gitStatusStore": "既定は git 状態を持たない縮退状態(DisabledGitFileIndex と同じ位置づけ)",
    ]

    /// `name: Type = Type(` と `name: Type = .init(` の形（型名と同じ型を新しく作る
    /// 既定値）を拾う。型名の末尾で共有物の形（Preference / Store / Defaults）に絞る。
    /// `.init(` を含めるのは、これを落とすと同じ意味の書き方で検査を素通りできるため
    /// （実測: 検査を書いた直後に `= .init()` へ書き換えたら通ってしまった）。
    private static let patternSource =
        #"^\s*([a-zA-Z][A-Za-z0-9]*): ([A-Z][A-Za-z0-9]*(?:Preference|Store|Defaults)) = (?:\2|\.init)\("#

    private static func sourceURL(_ relativePath: String) -> URL {
        // このテストファイルは BefoldApp/befoldTests/ にある。
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }

    private static func defaultedArguments(in relativePath: String) throws -> [String] {
        let source = try String(contentsOf: sourceURL(relativePath), encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: patternSource, options: [.anchorsMatchLines])
        let range = NSRange(source.startIndex ..< source.endIndex, in: source)
        return pattern.matches(in: source, range: range).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        }
    }

    @Test("共有ストア・表示設定を受け取る init 引数に既定値が付いていない")
    func sharedDependenciesHaveNoDefaultArguments() throws {
        for path in Self.sources {
            for argument in try Self.defaultedArguments(in: path) {
                #expect(
                    Self.allowed[argument] != nil,
                    """
                    \(path) の引数 '\(argument)' に既定値が付いている。渡し忘れが\
                    コンパイルエラーにならず、静かに別インスタンスになる(TASK-319 / TASK-558)。\
                    既定値を外すか、共有インスタンスの受け渡しでないなら allowed へ理由つきで足すこと。
                    """
                )
            }
        }
    }

    /// 例外リストが実態から取り残されていないことも見る。外した引数が allowed に
    /// 残り続けると、次に同じ名前の引数へ既定値が付いても素通りする。
    @Test("既定値の例外リストに実体のないエントリが残っていない")
    func allowListHasNoStaleEntries() throws {
        var found: Set<String> = []
        for path in Self.sources {
            try found.formUnion(Self.defaultedArguments(in: path))
        }
        #expect(Set(Self.allowed.keys) == found)
    }
}
