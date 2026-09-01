import AppKit
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
    @Bindable var model: PDFPageIndicatorModel

    var body: some View {
        if model.pageCount > 0 {
            content
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
                .padding(12)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isEditing { input } else { label }
    }

    /// 通常の表示。クリックで入力へ変わる（TASK-578.2）。
    ///
    /// **`Button` を使う。`onTapGesture` では反応しない。** この面は AppKit がホストする
    /// `PDFView` の上に重なる SwiftUI で、実機で試したところ合成クリックでも `AXPress`
    /// でもタップジェスチャが発火しなかった（右上の回転コントロールが `Button` で
    /// 動いているので、そちらへ合わせる）。
    ///
    /// **ボタンの枠は出さない**（`.plain`）。常時出ているものが押せそうな枠を持つと
    /// 読んでいる最中に主張しすぎるので、押せることはポインタの形と tooltip で伝える。
    private var label: some View {
        Button {
            model.beginEditing()
        } label: {
            Text(verbatim: "\(model.currentIndex + 1) / \(model.pageCount)")
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 押せることをポインタで伝える。`pointerStyle(_:)` は macOS 15 以降なので
        // （このアプリの下限は 14）、カーソルを直接差し替える。
        .onHover { isInside in
            if isInside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        // 数字だけでは何の値か伝わらないので、読み上げには意味を付ける。
        .accessibilityLabel(
            String(
                format: String(localized: "viewer.pdf.pageIndicator", bundle: .l10n),
                model.currentIndex + 1,
                model.pageCount
            )
        )
        .help(String(localized: "viewer.pdf.pageJump", bundle: .l10n))
    }

    /// ページ番号の入力。確定（Enter）で飛び、Esc で捨てて戻る。
    ///
    /// **総ページ数はそのまま残す。** 入れられる範囲がその場で分かるので、
    /// 範囲外を打って弾かれる前に気づける。
    private var input: some View {
        HStack(spacing: 2) {
            // **入力欄には地を敷く。** 敷かないと通常表示とほぼ同じ見た目になり、
            // いま打ち込めるのかが画面から分からない（実機で確認 / TASK-578.2）。
            FocusClaimingTextField(
                text: $model.draft,
                alignment: .right,
                font: .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                onSubmit: model.commit,
                onCancel: model.cancel
            )
            .frame(width: 32, height: 14)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(String(localized: "viewer.pdf.pageJump", bundle: .l10n))
            Text(verbatim: "/ \(model.pageCount)")
                .foregroundStyle(.secondary)
        }
    }
}
