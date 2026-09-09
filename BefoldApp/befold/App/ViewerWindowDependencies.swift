import BefoldKit
import Foundation

/// 窓の生成経路(`ViewerWindowManager` → `ViewerWindowController`)を素通しする共有物の束。
///
/// ここに入っているのはいずれも**アプリ全体で 1 個**の表示設定・ストアで、`AppStores` が
/// 唯一のインスタンスを持つ。マネージャもコントローラも中身を選ばず丸ごと受け渡すため、
/// 共有物を足すときに片方の経路だけ配線し忘れる形にならない。
///
/// **init に既定値を一切付けない。** 付けると構築点での渡し忘れがコンパイルエラーに
/// ならず、静かに別インスタンスになる(TASK-319。窓ごとに `DiffDisplayPreference` が
/// 生まれて 2 窓でトグルが同期しなかった)。この規則は
/// `SharedDependencyDefaultsTests` がこのファイルの宣言を読んで検証する。
///
/// 次のものは**意図的に入れていない**。
/// - `windowFrame`: `ViewerWindowController` は受け取らない。束へ入れると窓側から
///   見えるようになるが、これは「解決結果を書き戻さない」と決めた相手(TASK-583)なので
///   見える範囲を広げない。`ViewerWindowManager` の stored property のまま。
/// - `diffLoader`: 両側で型が違う(マネージャは非 Optional = この型が唯一の持ち主、
///   コントローラは `GitDiffLoader?` で nil = 差分を取りに行かない)。1 フィールドへ
///   畳むとどちらかの性質を捨てることになるため、両側の引数として残す。
/// - `gitFileIndex` / `gitStatusStore`: 既定が「git を起動しない縮退状態」で、
///   共有インスタンスの受け渡しではなく実装の選択。
@MainActor
struct ViewerWindowDependencies {
    let displayDefaults: SidebarDisplayDefaults
    let diffDisplayPreference: DiffDisplayPreference
    let findOptionsPreference: FindOptionsPreference
    let headingJumpLevelDefaults: HeadingJumpLevelDefaults
    let codeFontPreference: CodeFontPreference
    let csvNumberFormatPreference: CsvNumberFormatPreference
    let perFileState: PerFileStateStore
    let bookmarkStore: BookmarkStore
}
