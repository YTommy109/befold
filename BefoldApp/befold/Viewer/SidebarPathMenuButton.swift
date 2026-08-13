import AppKit
import BefoldKit
import SwiftUI

/// サイドバーヘッダーのフォルダー名。押すと上位の祖先をホームまで並べたメニューが開き、
/// 選んだ階層へ移動する(Finder のウィンドウタイトル ⌘クリックと同じモデル)。
///
/// かつては一覧の先頭に `..` 行を置いて 1 階層ずつ上がっていた(TASK-475 で廃止)。
/// 多階層の移動が 1 操作で済むうえ、一覧の行を占有しない。
///
/// **祖先が無い(ホーム自身・ホーム外)ときはメニューを出さず素のテキストに落とす。**
/// 空のメニューが開く状態を作らないためで、指示子も出ないので「押せない」ことが
/// 見た目と一致する。判定は `SidebarPathMenu.ancestors` の結果だけを見る。
struct SidebarPathMenuButton: View {
    let directory: URL
    /// 移動の上限。呼び出し側が渡す(既定値を持たせると渡し忘れが静かに実ホームを見る)。
    let home: URL
    let onNavigate: (URL) -> Void

    @State private var isHovered = false

    var body: some View {
        // 祖先の解決は `normalizedPathKey`(resolvingSymlinksInPath)を階層ぶん呼ぶ。
        // body は表示のたびに評価されるので、ここで 1 回だけ採ってメニューの
        // 中身と「押せるか」の両方に使い回す。
        let ancestors = SidebarPathMenu.ancestors(of: directory, home: home)
        if ancestors.isEmpty {
            folderName
        } else {
            menu(ancestors: ancestors)
        }
    }

    private var folderName: some View {
        Text(directory.lastPathComponent)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func menu(ancestors: [URL]) -> some View {
        Menu {
            ForEach(ancestors, id: \.self) { ancestor in
                Button {
                    onNavigate(ancestor)
                } label: {
                    Label {
                        Text(ancestor.lastPathComponent)
                    } icon: {
                        // サイドバー一覧の行アイコンと同じ 16pt に揃える。
                        // SwiftUI の `Menu` の中身は AppKit の `NSMenu` へ変換され、
                        // 画像は `NSImage.size` のまま描かれる(`.resizable()` /
                        // `.frame` は効かない)。NSImage 側を縮める。
                        Image(nsImage: NSMenuItem.icon(forFile: ancestor.path))
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                folderName
                // 押下可能を示す指示子。`menuIndicator` は borderlessButton だと
                // ラベルの外に付いてフォルダー名の省略と噛み合わないため、
                // ラベルの一部として自前で出す。
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // ホバーで押せることを伝える。borderlessButton のメニューは枠が無く、
            // 反応が無いと静的なタイトルと見分けが付かない。
            .contentShape(.rect)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
            )
            .onHover { isHovered = $0 }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "sidebar.path.menu.help", bundle: .l10n))
    }
}
