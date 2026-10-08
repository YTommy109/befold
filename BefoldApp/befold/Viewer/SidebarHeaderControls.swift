import BefoldKit
import SwiftUI

/// サイドバーヘッダーの操作行のボタン群。
///
/// 何をどこに出すかは `SidebarHeaderControlsModel` が決める。ここは受け取った記述を
/// 描いて、押されたら**どのボタンが押されたか(Kind)を発行するだけ**にしてある。
/// 押した先で何をするかの対応表は `SidebarHeaderView.selectControl(_:)` が 1 箇所で持つ。
///
/// **ボタンごとにクロージャを持たない(TASK-590)。** トグルごとの optional クロージャを
/// 並べると、対応の入れ替えや `{}` での埋め忘れがコンパイルを通り、ユニットテストの
/// 通らない場所(SwiftUI ビューの中)に配線が残る。Kind を 1 本で発行すれば、この型に
/// 残る判断は無くなり、対応表はテストで固定できる場所へ移る。
struct SidebarHeaderControls: View {
    /// 左群と右群のどちらを描くか。
    enum Placement {
        case leading
        case trailing
    }

    let controls: SidebarHeaderControlsModel
    let placement: Placement
    /// ボタンが押された。`.overflow` は `Menu` が自前で開くので、ここからは発行されない。
    let onSelectControl: (SidebarHeaderControl.Kind) -> Void
    /// ⋯ の項目が選ばれた。項目は自分が起こす切り替えを持っているので、**ここでも
    /// 対応表を挟まない**(TASK-592)。
    let onSelectOverflowItem: (SidebarDisplayChange) -> Void
    /// 「変更のあるファイルのみ」の ▾ で比較基準が選ばれた。
    let onSelectComparisonTarget: (GitComparisonTarget) -> Void

    var body: some View {
        ForEach(items, id: \.kind) { control in
            switch control.kind {
            case .overflow:
                overflowMenu(control)
            case .changedFilesOnly:
                changedFilesOnlyMenu(control)
            default:
                button(control)
            }
        }
    }

    private var items: [SidebarHeaderControl] {
        placement == .leading ? controls.leading : controls.trailing
    }

    /// - Parameter helpDetail: ツールチップの 2 行目(あれば)。
    private func button(_ control: SidebarHeaderControl, helpDetail: String? = nil) -> some View {
        Button {
            onSelectControl(control.kind)
        } label: {
            icon(control)
        }
        .buttonStyle(.borderless)
        .help(
            String(localized: String.LocalizationValue(control.helpKey), bundle: .l10n)
                + (helpDetail.map { "\n" + $0 } ?? "")
        )
    }

    private func overflowMenu(_ control: SidebarHeaderControl) -> some View {
        Menu {
            ForEach(controls.overflowItems, id: \.change) { item in
                Button {
                    onSelectOverflowItem(item.change)
                } label: {
                    // チェックは Label ではなくテキスト側に持たせる(Menu 内の Toggle は
                    // 3 項目のうち 2 つが排他選択で意味がずれるため使わない)。
                    if item.isChecked {
                        Label(title(for: item), systemImage: "checkmark")
                    } else {
                        Text(title(for: item))
                    }
                }
            }
        } label: {
            icon(control)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: String.LocalizationValue(control.helpKey), bundle: .l10n))
    }

    /// クリックで絞り込みの ON/OFF、▾ で比較基準を選ぶ。
    ///
    /// `Menu(primaryAction:)` は使わない: borderlessButton 風の描画ではアイコンの色(絞り込み
    /// 中のアクセント)が反映されず、項目のチェックも出なかった(TASK-678 の実機確認)。
    /// 本体は他と同じ `button()`、▾ は独立した `Menu` で、色とチェックは標準の経路に乗せる。
    private func changedFilesOnlyMenu(_ control: SidebarHeaderControl) -> some View {
        let basis = ComparisonTargetPresentation.title(for: controls.comparisonTarget)
        return HStack(spacing: 0) {
            button(control, helpDetail: basis)
            Menu {
                Picker(selection: Binding(
                    get: { controls.comparisonTarget },
                    set: onSelectComparisonTarget
                )) {
                    ForEach(controls.comparisonItems, id: \.target) { item in
                        Text(ComparisonTargetPresentation.title(for: item.target)).tag(item.target)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(basis)
            .accessibilityLabel(basis)
        }
    }

    private func icon(_ control: SidebarHeaderControl) -> some View {
        Image(systemName: control.systemImage)
            .foregroundStyle(control.isAccented ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }

    private func title(for item: SidebarOverflowItem) -> String {
        String(localized: String.LocalizationValue(item.titleKey), bundle: .l10n)
    }
}
