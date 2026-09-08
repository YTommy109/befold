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
    let onSelectOverflowItem: (SidebarOverflowItem.Kind) -> Void

    var body: some View {
        ForEach(items, id: \.kind) { control in
            switch control.kind {
            case .overflow:
                overflowMenu(control)
            default:
                button(control)
            }
        }
    }

    private var items: [SidebarHeaderControl] {
        placement == .leading ? controls.leading : controls.trailing
    }

    private func button(_ control: SidebarHeaderControl) -> some View {
        Button {
            onSelectControl(control.kind)
        } label: {
            icon(control)
        }
        .buttonStyle(.borderless)
        .help(String(localized: String.LocalizationValue(control.helpKey), bundle: .l10n))
    }

    private func overflowMenu(_ control: SidebarHeaderControl) -> some View {
        Menu {
            ForEach(controls.overflowItems, id: \.kind) { item in
                Button {
                    onSelectOverflowItem(item.kind)
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

    private func icon(_ control: SidebarHeaderControl) -> some View {
        Image(systemName: control.systemImage)
            .foregroundStyle(control.isAccented ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }

    private func title(for item: SidebarOverflowItem) -> String {
        String(localized: String.LocalizationValue(item.titleKey), bundle: .l10n)
    }
}
