import SwiftUI

/// フォルダー一覧の 1 行。`FileListEntryRow`(サイドバーと共有)は無変更で包み、
/// 右に変更日・サイズ・種類を足す(TASK-707)。
///
/// 幅が狭いときは名前が中間省略されるだけで、列は折り返さず固定幅のまま残す。
/// 読み上げは名前と 3 項目を 1 行にまとめる。
struct FolderListingRow: View {
    let entry: FileListEntry
    /// nil は未取得(または読めなかった)。この間は名前だけの行になる。
    let metadata: FolderListingMetadata?

    var body: some View {
        HStack(spacing: 8) {
            FileListEntryRow(entry: entry)
            if let metadata {
                Group {
                    Text(metadata.modified?.formatted(date: .numeric, time: .shortened) ?? "")
                        .frame(width: 120, alignment: .trailing)
                    Text(metadata.size?.formatted(.byteCount(style: .file)) ?? "")
                        .frame(width: 64, alignment: .trailing)
                    Text(metadata.kind ?? "")
                        .frame(width: 150, alignment: .leading)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
