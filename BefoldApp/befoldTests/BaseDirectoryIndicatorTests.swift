@testable import befold
import BefoldKit
import Foundation
import Testing

/// サイドバーヘッダーの基準ディレクトリ表示が、`BaseDirectoryDescriptor.Kind` の
/// 3 種別を取り違えないことを固定する(TASK-438.1)。
///
/// とくに「git リポジトリだが befold では扱えない」を「通常フォルダ」と説明しないこと。
/// これは静かな縮退ではなく事実と異なる表示であり、ADR の Fallback 方針
/// (モーダルを出さずに git 機能だけ落とす)とは別の問題。
@MainActor
struct BaseDirectoryIndicatorTests {
    private func indicator(for lookup: GitRootLookup) -> BaseDirectoryIndicator {
        BaseDirectoryIndicator(
            base: BaseDirectoryDescriptor(
                rootLookup: lookup,
                workspaceRoot: URL(fileURLWithPath: "/Users/me/repo")
            )
        )
    }

    private var plainFolderLabel: String {
        String(localized: "sidebar.baseDirectory.plainFolder", bundle: .l10n)
    }

    @Test("扱えないリポジトリを通常フォルダとして説明しない")
    func doesNotDescribeUnusableRepositoryAsPlainFolder() {
        let tooltip = indicator(for: .undetermined).tooltip
        #expect(!tooltip.contains(plainFolderLabel))
        #expect(tooltip.contains(String(localized: "sidebar.baseDirectory.unusableRepository", bundle: .l10n)))
    }

    @Test("扱えないリポジトリでも git のアイコンを出す")
    func keepsGitIconForUnusableRepository() {
        #expect(indicator(for: .undetermined).iconName == indicator(for: .root(URL(fileURLWithPath: "/r"))).iconName)
        #expect(indicator(for: .notARepository).iconName == "folder")
    }

    /// 失敗理由の種別(partial clone / reftable / 未知の拡張)を文言に出さない。
    /// `GitLibrary.OpenFailure` は 3 つを `.unusable` の 1 値へ畳んでおり、
    /// 理由別の文言は型が持っていない情報を騙ることになる(TASK-438)。
    @Test("扱えないリポジトリの文言に失敗理由の種別を出さない")
    func doesNotNameTheFailureReason() {
        let tooltip = indicator(for: .undetermined).tooltip.lowercased()
        for reason in ["partial", "reftable", "extension", "clone"] {
            #expect(!tooltip.contains(reason))
        }
    }

    @Test("3 種別のツールチップがそれぞれ異なる")
    func distinguishesAllThreeKinds() {
        let tooltips = [
            indicator(for: .root(URL(fileURLWithPath: "/Users/me/repo"))).tooltip,
            indicator(for: .notARepository).tooltip,
            indicator(for: .undetermined).tooltip,
        ]
        #expect(Set(tooltips).count == 3)
    }
}
