import BefoldKit
import SwiftUI

/// サイドバー上部の見出し行(基準ディレクトリ・フォルダー名・表示切り替えの各トグル・
/// 名前フィルター欄)。
///
/// `FileListView` から分けているのは、ここが扱うのが「一覧の見せ方の切り替え」であって
/// 一覧行の描画ではないため(TASK-443)。表示設定のトグルを増やすときに触るのはこの型だけで、
/// 行・コンテキストメニュー・キー操作には影響しない。
///
/// 各トグルの真実の源は `SidebarDisplayDefaults` で、`model` の値はその写し。
/// ここは写しを読んで見た目を決め、切り替えの実行は `FileListViewDelegate` で
/// 上位(ViewerWindowController)へ返す。**トグルごとにクロージャを注入しない**
/// ——種別は `SidebarDisplayChange` の値で表す(TASK-586)。
struct SidebarHeaderView: View {
    @Bindable var model: FileListModel
    /// 表示切り替えと、フォルダー名のパスポップアップが起こす移動の受け手。
    ///
    /// **移動用のクロージャを別に増やさない。** ⌘↑ / delete と同じ
    /// `fileListDidRequestNavigation(to:)` を通すことで、上へ移動する経路が 1 本に
    /// 保たれる(TASK-475)。ウィンドウ側が保持するため弱参照で持つ。
    weak var delegate: FileListViewDelegate?

    @FocusState private var isFilterFieldFocused: Bool

    /// **delegate は必須引数(TASK-590)。** memberwise init に任せると `weak var` の
    /// 暗黙 `= nil` で `SidebarHeaderView(model:)` が通り、すべてのトグルが「押しても
    /// 何も起きないボタン」へ静かに倒れる。`FileListView` の弱参照の写しを受けるため
    /// 型は optional だが、既定値は置かない。
    init(model: FileListModel, delegate: FileListViewDelegate?) {
        self.model = model
        self.delegate = delegate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            baseDirectoryIndicator
            navigationHeader
            if model.transient.isFilterActive {
                filterField
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var filterField: some View {
        @Bindable var transient = model.transient
        return TextField(
            String(localized: "sidebar.filter.placeholder", bundle: .l10n),
            text: $transient.filterText
        )
        .textFieldStyle(.plain)
        .focused($isFilterFieldFocused)
        .onAppear { isFilterFieldFocused = true }
        .onKeyPress(.escape) {
            model.transient.closeFilter()
            return .handled
        }
    }

    /// 基準ディレクトリの解決前(初回表示直後の一瞬)は行を出さない。
    @ViewBuilder
    private var baseDirectoryIndicator: some View {
        if let base = model.baseDirectory {
            BaseDirectoryIndicator(base: base)
        }
    }

    private var controls: SidebarHeaderControlsModel {
        SidebarHeaderControlsModel(
            settings: model.displaySettings,
            canFilterChangedFiles: model.canFilterChangedFiles,
            isFilterActive: model.transient.isFilterActive,
            isFilterTextEmpty: model.transient.filterText.isEmpty
        )
    }

    /// 左＝一覧の形、右＝絞り込み。位置がその系統を表しているので、ボタンを足すときは
    /// どちらの群かを先に決めること(並びは SidebarHeaderControlsModelTests が固定している)。
    private var navigationHeader: some View {
        HStack {
            headerControls(placement: .leading)
            SidebarPathMenuButton(
                directory: model.currentDirectory,
                home: DirectoryLister.defaultHome,
                onNavigate: { delegate?.fileListDidRequestNavigation(to: $0) }
            )
            Spacer()
            headerControls(placement: .trailing)
        }
    }

    /// 受け口のメソッドをそのまま渡す。**ここで包みクロージャを書かない**——
    /// 包むとテストの通らない場所に配線が戻る(TASK-590)。⋯ の項目は自分が起こす
    /// 切り替えを持っているので、`perform` へ直結できる(TASK-592)。
    private func headerControls(placement: SidebarHeaderControls.Placement) -> some View {
        SidebarHeaderControls(
            controls: controls,
            placement: placement,
            onSelectControl: selectControl,
            onSelectOverflowItem: perform
        )
    }

    /// ヘッダーのボタン Kind → 動作の対応表。**ボタンの中に分岐を書かない**——
    /// ボタンを足したときに配線漏れが起きたかどうかを、この表のテスト
    /// (`SidebarDisplayChangeRoutingTests`)で測れる。テストから呼べるよう internal。
    func selectControl(_ kind: SidebarHeaderControl.Kind) {
        switch kind {
        case .layoutMode: perform(.toggleLayoutMode)
        case .changedFilesOnly: perform(.toggleChangedFilesOnly)
        // 名前フィルターは delegate へ上げない。一覧の絞り込みは窓の一時状態で、
        // 表示 4 値(SidebarDisplayDefaults)には属さない。
        case .filter: toggleFilter()
        // ⋯ は Menu が自前で開き、項目の選択は selectOverflowItem が受ける。
        case .overflow: break
        }
    }

    private func toggleFilter() {
        if model.transient.isFilterActive {
            model.transient.closeFilter()
        } else {
            model.transient.isFilterActive = true
        }
    }

    /// 表示切り替えを delegate へ配る唯一の口。
    private func perform(_ change: SidebarDisplayChange) {
        delegate?.fileListDidRequestDisplayChange(change)
    }
}
