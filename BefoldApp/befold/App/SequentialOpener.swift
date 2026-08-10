import Foundation

/// 複数の URL を「渡された順にウィンドウが出る」ように逐次で開く。
///
/// オープンは 1 件ごとに実 FS の存在確認・列挙(`DirectoryLister.resolveFileToOpen`)を待つ。
/// 件数分の Task を張って並行に走らせると、解決の完了順でウィンドウの生成順が決まり、
/// どれがキーウィンドウになるかも任意になる。逐次であることをこの 1 箇所に閉じ込め、
/// 複数 URL を受け取る入口(`AppDelegate.openSequentially`)をここへ合流させる。
///
/// 開く処理そのものを引数で受けるのは、順序の保証だけを実ウィンドウ生成なしで
/// 検証できるようにするため(`SequentialOpenerTests`)。
enum SequentialOpener {
    static func open(_ urls: [URL], using open: @MainActor (URL) async -> Void) async {
        for url in urls {
            await open(url)
        }
    }
}
