import BefoldKit
import SwiftUI

/// Quick Open パネルの中身。入力欄と候補リストだけを持ち、判断は `QuickOpenModel` に委ねる。
struct QuickOpenView: View {
    @Bindable var model: QuickOpenModel
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

    private func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        guard QuickOpenKeyAction.action(for: key) != nil else { return .ignored }
        perform(key)
        return .handled
    }

    private func perform(_ key: KeyEquivalent) {
        switch QuickOpenKeyAction.action(for: key) {
        case let .moveSelection(offset):
            model.moveSelection(by: offset)
        case .completePath:
            Task { await model.completePath() }
        case .commit:
            // パネルを閉じるのは決定経路(onOpen 内の dismiss)だけに一本化する。
            // ここで無条件に閉じると、開ける対象が無い Enter でもパネルが黙って
            // 消えてしまう。開けたときは onOpen が畳んでから開く。
            Task { await model.commitSelection() }
        case .dismiss:
            onDismiss()
        case nil:
            break
        }
    }

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "quickOpen.placeholder", bundle: .l10n),
                text: $model.queryText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 20))
            .focused($isFieldFocused)
            // キーと動作の対応は QuickOpenKeyAction が持つ。ここに直接書くと
            // Help > キーボードショートカット に載せる情報源が無くなる(TASK-503)。
            .onSubmit { perform(.return) }
            .onKeyPress(.upArrow) { handle(.upArrow) }
            .onKeyPress(.downArrow) { handle(.downArrow) }
            .onKeyPress(.tab) { handle(.tab) }
            .onKeyPress(.escape) { handle(.escape) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var resultList: some View {
        if model.showsEnumerationFailure {
            notice(String(localized: "folder.enumerationFailed", bundle: .l10n))
        } else if model.showsNoMatches {
            notice(String(localized: "quickOpen.noMatches", bundle: .l10n))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.candidates.enumerated()), id: \.element.url) { index, candidate in
                            row(candidate, isSelected: index == model.selectedIndex)
                                // 行の identity は ForEach と同じ候補 URL に揃える。
                                // 位置 index を id にすると、絞り込みで候補が入れ替わっても
                                // SwiftUI が同じ行を使い回して内容を更新しない(リストが固まる)。
                                .id(candidate.url)
                        }
                        if model.showsTruncationNotice {
                            notice(String(localized: "quickOpen.truncated", bundle: .l10n))
                        }
                    }
                }
                .frame(maxHeight: 360)
                // キーボードで選択を動かしたとき、選択行が隠れたままにならないようにする。
                .onChange(of: model.selectedIndex) { _, index in
                    guard model.candidates.indices.contains(index) else { return }
                    proxy.scrollTo(model.candidates[index].url)
                }
            }
        }
    }

    private func row(_ candidate: QuickOpenCandidate, isSelected: Bool) -> some View {
        // 一致位置は displayPath 上のインデックス。ファイル名は displayPath の末尾なので
        // 名前側にはオフセットを引いて、名前部分に落ちる一致だけを強調する。
        let highlights = Set(model.highlightedIndices(in: candidate))
        let name = candidate.url.lastPathComponent
        let nameStart = candidate.displayPath.count - name.count
        let nameHighlights = Set(highlights.compactMap { $0 >= nameStart ? $0 - nameStart : nil })

        return HStack(spacing: 8) {
            Image(systemName: iconName(for: candidate.origin))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(highlighted(name, indices: nameHighlights))
                    .lineLimit(1)
                Text(highlighted(candidate.displayPath, indices: highlights))
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

    /// 文字列を AttributedString にし、`indices`(Character 単位)の文字を強調する。
    /// 基底フォントの大きさは変えず、色(accentColor)と太字だけを載せる。
    private func highlighted(_ text: String, indices: Set<Int>) -> AttributedString {
        guard !indices.isEmpty else { return AttributedString(text) }
        var result = AttributedString()
        for (index, character) in text.enumerated() {
            var piece = AttributedString(String(character))
            if indices.contains(index) {
                piece.foregroundColor = .accentColor
                piece.inlinePresentationIntent = .stronglyEmphasized
            }
            result.append(piece)
        }
        return result
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
