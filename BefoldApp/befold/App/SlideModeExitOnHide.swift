/// サイドバーを畳んだときにスライドモードを解除する処理(TASK-585)。
///
/// `ViewerWindowAssembler` のクロージャに直接書かず切り出しているのは、クロージャの
/// 中身がユニットテストから呼べないため。**新しいクロージャは増やさない**
/// (`onSidebarDidHide` は既にある「畳んだ」の口に相乗りする)。
///
/// 幅の復元は呼び出し側が `ViewerSplitViewController.setSlideMode(false)` で行う。
/// ここが担うのは真値(`FileListModel.isSlideMode`)の解除だけ。
@MainActor
enum SlideModeExitOnHide {
    static func apply(to model: FileListModel) {
        model.setSlideMode(false)
    }
}
