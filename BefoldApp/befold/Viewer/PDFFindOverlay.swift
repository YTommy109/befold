import SwiftUI

/// PDF の右上に重ねる検索バー（TASK-570）。
///
/// **web 面のバー（viewer.html の `#mmd-bar`）と同じ形にする。** 入力欄・トグル・
/// 件数・前後移動・閉じるの並びと、右上という位置を揃えることで、面が違っても
/// 同じ機能だと分かる。見た目は `.regularMaterial` + 角丸 8 + `.separator` の枠で、
/// CSS 側の `--panel-bg` + `backdrop-filter: blur(8px)` に対応する。
///
/// 表示条件を自分で判断しない。この View を出すかどうかは `DocumentSurfaceStack` が
/// PDF の面と同じ条件で決める（条件は 1 箇所 / ADR 0002 段 2）。
///
/// **トグルは大文字小文字の区別だけ。** PDFKit の検索が受けるのは
/// `.caseInsensitive` / `.literal` / `.backwards` だけで、単語一致・正規表現に
/// 対応する引数が無い（SDK ヘッダ実測）。`PDFPage.selectionForRange:` と
/// `NSRegularExpression` で自前に組めばページ内に限り実現できるが、非同期検索の
/// 経路を丸ごと置き換えることになるので採らない。**このため web 面のバーとは
/// トグルの数が違う。** 効かないトグルを無効で並べるより、無い方が誤解が少ない。
struct PDFFindOverlay: View {
    /// 検索の状態。View はこれを読み書きするだけで、面には触らない。
    @Bindable var model: PDFFindModel
    /// 大文字小文字を区別するか。アプリ全体の設定（`FindOptionsPreference`）と共有する。
    let caseSensitive: Bool
    /// 大文字小文字の区別を切り替える。設定の保存は窓の外が持つ。
    let onToggleCaseSensitive: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            inputField
            Text(model.countText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(minWidth: 52)
                .lineLimit(1)
            navButton(symbol: "chevron.up", labelKey: "viewer.pdf.find.previous") {
                model.moveToPrevious()
            }
            navButton(symbol: "chevron.down", labelKey: "viewer.pdf.find.next") {
                model.moveToNext()
            }
            navButton(symbol: "xmark", labelKey: "viewer.pdf.find.close") {
                model.close()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
        .padding(12)
        // 開いたら入力欄へフォーカスが載る。**その仕事は入力欄自身が持つ**
        // （`FocusClaimingTextField` が窓へ入った 1 周後に `makeFirstResponder` する）。
        // かつてここに `.task { isInputFocused = true }` を置いていたが、この面では
        // `@FocusState` で first responder が移らないため効いていなかった（TASK-579）。
        //
        // Esc で閉じる。Help の一覧（`ViewerShortcutCatalog.findOnlyItems` の
        // `shortcuts.viewer.findClose` = 「検索バーを閉じる」）は種別非依存に出るので、
        // ここを繋がないと PDF でだけ説明と実態が食い違う（TASK-570 の AC #9）。
        // web 面は viewer-src/keyboard.ts の `resolveBarCloseKey` が同じ役割を持つ。
        // **入力欄に居るあいだの Esc は入力欄が受ける**（`onExitCommand` は first
        // responder が SwiftUI 側に無いと呼ばれない）ので、両方を繋いである。
        .onExitCommand { model.close() }
    }

    private var inputField: some View {
        HStack(spacing: 2) {
            FocusClaimingTextField(
                text: Binding(get: { model.query }, set: { model.setQuery($0) }),
                placeholder: String(localized: "viewer.pdf.find.placeholder", bundle: .l10n),
                font: .systemFont(ofSize: 13),
                // Enter で次へ（web 面の入力欄と同じ）。
                onSubmit: { model.moveToNext() },
                onCancel: { model.close() }
            )
            .frame(width: 160)

            toggle(
                symbol: "textformat",
                labelKey: "viewer.pdf.find.matchCase",
                isOn: caseSensitive,
                action: onToggleCaseSensitive
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.5)))
    }

    private func toggle(
        symbol: String,
        labelKey: String.LocalizationValue,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let label = String(localized: labelKey, bundle: .l10n)
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? Color.accentColor : .clear)
                )
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }

    private func navButton(
        symbol: String, labelKey: String.LocalizationValue, action: @escaping () -> Void
    ) -> some View {
        let label = String(localized: labelKey, bundle: .l10n)
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }
}
