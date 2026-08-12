import AppKit
import BefoldKit

/// 「開けなくなったブックマーク」の確認・報告アラート(GUI 層・自動テスト対象外)。
///
/// 確認では**件数だけでなく対象のパスを必ず出す**。`fileExists == false` は
/// 「削除された」「外部ボリュームがアンマウント中」「権限で見えない」を区別しないため、
/// 件数だけを見せると一時的に見えていないだけのパスをユーザーが承認して消してしまう。
@MainActor
enum MissingBookmarksAlerts {
    /// パス一覧に載せる最大件数。これを超えた分は残り件数だけを伝える。
    private static let listedPathLimit = 10

    /// 欠落したブックマークを提示し、取り除いてよいかを問う。取り除くと答えたら true。
    static func confirmRemoval(of urls: [URL]) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "alert.missingBookmarks.confirm.message",
            bundle: .l10n
        )
        alert.informativeText = informativeText(for: urls)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "alert.missingBookmarks.remove", bundle: .l10n))
        alert.addButton(withTitle: String(localized: "alert.cancel", bundle: .l10n))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 欠落が 1 件も無かったことを伝える。
    static func reportNoneMissing() {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.missingBookmarks.none.message", bundle: .l10n)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// 対象パスの一覧(上限を超えた分は残り件数)。表示パスは FileNotFoundUI と同じく
    /// `normalizedPathKey` に揃え、経路によるシンボリックリンク解決の差を出さない。
    private static func informativeText(for urls: [URL]) -> String {
        var lines = urls.prefix(listedPathLimit).map(\.normalizedPathKey)
        let remainder = urls.count - lines.count
        if remainder > 0 {
            lines.append(String(
                localized: "alert.missingBookmarks.confirm.more \(remainder)",
                bundle: .l10n
            ))
        }
        return lines.joined(separator: "\n")
    }
}
