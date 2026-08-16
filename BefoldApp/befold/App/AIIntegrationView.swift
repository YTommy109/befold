import AppKit
import SwiftUI

/// Help > AI コーディングエージェント連携 の中身。
///
/// 画面の見出し・説明は表示言語に合わせて出すが、**skill ファイル本体は英語のまま**にする。
/// これはユーザーではなくコーディングエージェントが読む指示文であり、
/// 訳し分けると指示の効き方まで変わってしまうため。
struct AIIntegrationView: View {
    /// 画面に出し、コピーボタンがクリップボードへ入れる skill ファイルの内容。
    /// 「説明文ではなく skill 本体をコピーする」ことをテストから固定できるよう internal にする。
    let exampleSkill: String
    /// 読み込みに失敗した場合はコピーさせない（失敗文言をコピーさせても意味がない）。
    private let isSkillAvailable: Bool
    /// コピー直後だけボタンの文言を「コピーしました」に差し替えるための状態。
    @State private var didCopy = false
    /// 文言を戻すためのタイマー。連打しても最後のコピーから数え直す。
    @State private var resetTask: Task<Void, Never>?

    init() {
        if let url = Bundle.appResources.url(forResource: "befold-review-skill", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8)
        {
            exampleSkill = text.trimmingCharacters(in: .whitespacesAndNewlines)
            isSkillAvailable = true
        } else {
            exampleSkill = String(localized: "aiIntegration.loadFailed", bundle: .l10n)
            isSkillAvailable = false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("aiIntegration.detail", bundle: .l10n)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                cliRequirement
                copyButton
                Text(exampleSkill)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    // 背景ごとウィンドウ幅まで広げる。行の長さに合わせると右側が
                    // 大きく空き、コードブロックに見えなくなる。
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    /// skill は `command -v befold` で CLI が無ければ黙ってスキップする作りなので、
    /// CLI が未導入だと「skill を保存したのに何も起きない」状態になる。
    /// 前提であることと、App メニューからの導線を画面に出しておく。
    private var cliRequirement: some View {
        Label {
            Text("aiIntegration.cliRequired", bundle: .l10n)
        } icon: {
            Image(systemName: "terminal")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        // 囲みは行の長さではなくウィンドウ幅に合わせる（説明本文と同じ扱いにする）。
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    /// skill ボックスの右上に置くアイコンボタン。コピー直後だけチェックマークに変わる。
    /// 枠のあるボタンスタイルにするのは、アイコンだけだと押せることが伝わらないため。
    /// 文字を持たないので、ツールチップと VoiceOver 用の説明も必ず添える。
    private var copyButton: some View {
        let title = didCopy
            ? String(localized: "aiIntegration.copySkill.done", bundle: .l10n)
            : String(localized: "aiIntegration.copySkill", bundle: .l10n)
        return HStack {
            Spacer()
            Button {
                copySkillToPasteboard()
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!isSkillAvailable)
            .help(Text("aiIntegration.copySkill.help", bundle: .l10n))
            .accessibilityLabel(title)
        }
    }

    /// skill ファイルとして保存すべき内容だけをクリップボードへ入れる
    /// （保存先パスの手順は画面の説明として残す）。
    private func copySkillToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(exampleSkill, forType: .string)
        didCopy = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}
