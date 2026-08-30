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
/// **単語一致と正規表現のトグルは出すが常に無効。** PDFKit の検索が受けるのは
/// `.caseInsensitive` / `.literal` / `.backwards` だけで、この 2 つに対応する引数が
/// 無い（SDK ヘッダ実測）。隠さず無効で出すのは、web 面で ON にしたまま PDF を
/// 開いたときに「同じ設定なのに結果が違う」形を避けるため——押せないことと
/// tooltip で、ここでは効かないと伝える。
struct PDFFindOverlay: View {
    /// 検索の状態。View はこれを読み書きするだけで、面には触らない。
    @Bindable var model: PDFFindModel
    /// 大文字小文字を区別するか。アプリ全体の設定（`FindOptionsPreference`）と共有する。
    let caseSensitive: Bool
    /// 大文字小文字の区別を切り替える。設定の保存は窓の外が持つ。
    let onToggleCaseSensitive: () -> Void

    @FocusState private var isInputFocused: Bool

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
        .onAppear { isInputFocused = true }
        // Esc で閉じる。Help の一覧（`ViewerShortcutCatalog.findOnlyItems` の
        // `shortcuts.viewer.findClose` = 「検索バーを閉じる」）は種別非依存に出るので、
        // ここを繋がないと PDF でだけ説明と実態が食い違う（TASK-570 の AC #9）。
        // web 面は viewer-src/keyboard.ts の `resolveBarCloseKey` が同じ役割を持つ。
        .onExitCommand { model.close() }
    }

    private var inputField: some View {
        HStack(spacing: 2) {
            TextField(
                String(localized: "viewer.pdf.find.placeholder", bundle: .l10n),
                text: Binding(get: { model.query }, set: { model.setQuery($0) })
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .frame(width: 160)
            .focused($isInputFocused)
            // Enter で次へ（web 面の入力欄と同じ）。IME の変換確定は SwiftUI の
            // TextField が飲むので、こちらで keyCode 229 を見る必要は無い。
            .onSubmit { model.moveToNext() }

            toggle(
                symbol: "textformat",
                labelKey: "viewer.pdf.find.matchCase",
                isOn: caseSensitive,
                isEnabled: true,
                action: onToggleCaseSensitive
            )
            toggle(
                symbol: "textformat.abc.dottedunderline",
                labelKey: "viewer.pdf.find.wholeWord",
                isOn: false,
                isEnabled: false,
                action: {}
            )
            toggle(
                symbol: "asterisk",
                labelKey: "viewer.pdf.find.regex",
                isOn: false,
                isEnabled: false,
                action: {}
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
        isEnabled: Bool,
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
                // **使えないトグルは見て分かるようにする。** `.disabled()` だけでは
                // `foregroundStyle` の明示指定が勝ってしまい、有効なトグルと同じ濃さで
                // 出る（実機で確認 / TASK-570 の AC #6）。
                .foregroundStyle(isOn ? Color.white : Color.primary.opacity(isEnabled ? 1 : 0.3))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
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
