import BefoldKit
import Foundation

/// **ウィンドウの生存期間だけ**覚えておく、ファイル単位の表示状態
/// （スクロール位置・表示モード）。
///
/// スクロール位置は `scrollTop` の生ピクセル値で、内容・ウィンドウ幅・倍率・フォント
/// 設定のどれが変わっても意味を失う。表示モードは、ソース表示で見たいファイル
/// （コード種別）が保存値と無関係に常にソース表示になるため、永続化して得られる利得が
/// 小さい。どちらもアプリの再起動をまたいで復元すると害のほうが大きいので、
/// `UserDefaults` へは書かず、窓が閉じれば消える（TASK-565）。
///
/// **`UserDefaults` を引数にも stored property にも持たない。** 永続化できないことを
/// 型の依存で担保する。
///
/// **永続化する表示状態（倍率・サイドバー開閉・ウィンドウフレーム）はここに入れない。**
/// それらは内容に依存しないユーザーの意図なので `PerFileStateStore` 側が持つ。
/// 新しい候補が出たら、どちらの寿命なのかを決めてから足すこと。
///
/// 所有者は `ViewerDocumentPresenter`（窓ごとに 1 個）。`AppStores` から配ると
/// 全ウィンドウ共有になり、窓ごとの記憶という前提が崩れる。
@MainActor
final class WindowPresentationMemory {
    private var renderedPositions = PathKeyedTable<Double>()
    private var sourcePositions = PathKeyedTable<Double>()
    private var displayModes = PathKeyedTable<ViewerDisplayMode>()

    init() {}

    /// 指定ファイル・モードのスクロール位置。記憶が無ければ 0（先頭）。
    func scrollPosition(for url: URL, mode: ViewerBridge.ViewMode) -> Double {
        switch mode {
        case .rendered: renderedPositions.value(for: url) ?? 0
        case .source: sourcePositions.value(for: url) ?? 0
        }
    }

    /// 指定ファイル・モードのスクロール位置を記憶する。
    /// レンダリング表示とソース表示は DOM 構造が異なり位置に連続性がないため、
    /// モードごとに別の表へ独立して持つ。
    func setScrollPosition(_ position: Double, for url: URL, mode: ViewerBridge.ViewMode) {
        switch mode {
        case .rendered: renderedPositions.setValue(position, for: url)
        case .source: sourcePositions.setValue(position, for: url)
        }
    }

    /// 指定ファイルの表示モード。記憶が無ければレンダリング表示。
    func displayMode(for url: URL) -> ViewerDisplayMode {
        displayModes.value(for: url) ?? .rendered
    }

    /// 指定ファイルの表示モードを記憶する。
    func setDisplayMode(_ mode: ViewerDisplayMode, for url: URL) {
        displayModes.setValue(mode, for: url)
    }

    /// 記憶済みモードを、その種別で実際に成立するモードまで降格して返す。
    /// 降格しても記憶は書き換えない。
    func restoredDisplayMode(for url: URL) -> ViewerDisplayMode {
        displayMode(for: url).supported(for: url)
    }

    /// ファイルの rename / move に伴い、旧パスの記憶（位置 2 モード分・表示モード）を
    /// 新パスへ引き継ぐ。永続側の引き継ぎは `PerFileStateStore.migrate` が別に行う。
    func migrate(from oldURL: URL, to newURL: URL) {
        renderedPositions.migrateValue(from: oldURL, to: newURL)
        sourcePositions.migrateValue(from: oldURL, to: newURL)
        displayModes.migrateValue(from: oldURL, to: newURL)
    }
}
