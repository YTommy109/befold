import BefoldKit
import SwiftUI

/// Quick Open パネルの中身。入力欄と候補リストだけを持ち、判断は `QuickOpenModel` に委ねる。
struct QuickOpenView: View {
    let model: QuickOpenModel
    /// Esc で閉じる。パネルのライフサイクルは `QuickOpenPanelController` が持つ。
    let onDismiss: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            queryField
            Divider()
            resultList
        }
        .frame(width: 640)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { isFieldFocused = true }
    }

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "quickOpen.placeholder", bundle: .l10n),
                text: Binding(get: { model.queryText }, set: { model.queryText = $0 })
            )
            .textFieldStyle(.plain)
            .font(.system(size: 20))
            .focused($isFieldFocused)
            .onSubmit {
                // パネルを閉じるのは決定経路(onOpen 内の dismiss)だけに一本化する。
                // ここで無条件に閉じると、開ける対象が無い Enter でもパネルが黙って
                // 消えてしまう。開けたときは onOpen が畳んでから開く。
                model.commitSelection()
            }
            .onKeyPress(.upArrow) {
                model.moveSelection(by: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                model.moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.tab) {
                model.completePath()
                return .handled
            }
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var resultList: some View {
        if model.showsNoMatches {
            notice(String(localized: "quickOpen.noMatches", bundle: .l10n))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.candidates.enumerated()), id: \.element.url) { index, candidate in
                            row(candidate, isSelected: index == model.selectedIndex)
                                .id(index)
                        }
                        if model.showsTruncationNotice {
                            notice(String(localized: "quickOpen.truncated", bundle: .l10n))
                        }
                    }
                }
                .frame(maxHeight: 360)
                // キーボードで選択を動かしたとき、選択行が隠れたままにならないようにする。
                .onChange(of: model.selectedIndex) { _, index in
                    proxy.scrollTo(index)
                }
            }
        }
    }

    private func row(_ candidate: QuickOpenCandidate, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(for: candidate.origin))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.url.lastPathComponent)
                    .lineLimit(1)
                Text(candidate.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.25) : .clear)
        .contentShape(Rectangle())
    }

    private func iconName(for origin: QuickOpenCandidate.Origin) -> String {
        switch origin {
        case .recent: "clock"
        case .bookmark: "bookmark"
        case .indexed: "doc"
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
