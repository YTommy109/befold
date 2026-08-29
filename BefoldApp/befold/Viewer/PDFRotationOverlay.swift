import SwiftUI

/// PDF の右上に重ねる回転コントロール。
///
/// 回転はメニューではなくここに置く。**その面を見ているときにしか意味が無い操作**で、
/// 対象（いま出ているページ）が目の前にあるため、視線を離さず回せるほうがよい。
/// viewer 側のダイアグラム個別ズームが図の隅にコントロールを置いているのと同じ考え方。
///
/// 表示条件を自分で判断しない。この View を出すかどうかは
/// `DocumentSurfaceStack` が PDF の面と同じ条件で決める（条件は 1 箇所 / ADR 0002 段 2）。
struct PDFRotationOverlay: View {
    /// 90 度単位の回転を面へ届ける。時計回りが正。
    let onRotate: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            button(
                symbol: "rotate.left",
                labelKey: "viewer.pdf.rotateCounterClockwise",
                degrees: -90
            )
            button(
                symbol: "rotate.right",
                labelKey: "viewer.pdf.rotateClockwise",
                degrees: 90
            )
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5)
        )
        .padding(12)
    }

    private func button(
        symbol: String, labelKey: String.LocalizationValue, degrees: Int
    ) -> some View {
        let label = String(localized: labelKey, bundle: .l10n)
        return Button {
            onRotate(degrees)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        // 目印の無いアイコンだけのボタンなので、読み上げと tooltip の両方に名前を渡す。
        .accessibilityLabel(label)
        .help(label)
    }
}
