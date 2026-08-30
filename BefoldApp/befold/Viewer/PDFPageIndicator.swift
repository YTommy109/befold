import SwiftUI

/// PDF の左下に重ねる「現在ページ / 総ページ数」（TASK-578.1）。
///
/// **右上には置かない。** そこは回転（`PDFRotationOverlay`）と検索（`PDFFindOverlay`）が
/// 排他で使っており、常時表示のこれを足すと必ずどちらかと重なる。左下は空いている。
///
/// **でしゃばらない配色にする。** 読み終えるための情報であって操作対象ではないので、
/// 他のオーバーレイと同じ地（`.regularMaterial` + `.separator` の枠）に載せたうえで、
/// 文字は `.secondary` に落とす。色は指定せずセマンティックな指定に任せるので、
/// ライト / ダークの分岐を持たない（このリポジトリの慣習）。
///
/// 表示条件を自分で判断しない。この View を出すかどうかは `DocumentSurfaceStack` が
/// PDF の面と同じ条件で決める（条件は 1 箇所 / ADR 0002 段 2）。ただし
/// **総ページ数が 0 のときだけは自分で引っ込む**——「文書が無い」「面がまだ組み上がって
/// いない」のどちらでも 0 になり、`1 / 0` と描いてしまうため。
struct PDFPageIndicator: View {
    let model: PDFPageIndicatorModel

    var body: some View {
        if model.pageCount > 0 {
            Text(verbatim: "\(model.currentIndex + 1) / \(model.pageCount)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
                .padding(12)
                // 数字だけでは何の値か伝わらないので、読み上げには意味を付ける。
                .accessibilityLabel(
                    String(
                        format: String(localized: "viewer.pdf.pageIndicator", bundle: .l10n),
                        model.currentIndex + 1,
                        model.pageCount
                    )
                )
        }
    }
}
