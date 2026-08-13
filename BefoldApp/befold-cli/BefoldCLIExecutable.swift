import BefoldCLI

/// `befold` 実行ファイルの入口。**ここにロジックを書かないこと。**
///
/// CLI の実装は `BefoldCLI` framework にあり、この実行ファイルはそれを呼ぶだけ。
/// ロジックを実行ファイル側へ戻すと、それに触るテストが `xcodebuild test` の経路から
/// 外れる(Xcode は plain tool をテストホストにできない / TASK-456)。
@main
enum BefoldCLIExecutable {
    static func main() async {
        await BefoldCLIEntryPoint.run()
    }
}
