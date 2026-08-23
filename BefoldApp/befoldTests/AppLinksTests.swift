import BefoldKit
import Foundation
import Testing

/// アプリ外部リンクの単一情報源。
/// About パネルの導線は配布サイト側の参照元集計に載る必要があるため、
/// 配布サイトのホストと `ref` パラメータをここで固定する。
@Suite
struct AppLinksTests {
    @Test("homepage は配布サイト Worker を指す")
    func homepagePointsToDistributionSite() {
        #expect(AppLinks.homepage.host == "befold.degino.com")
    }

    @Test("homepage は参照元集計のための ref=about を持つ")
    func homepageCarriesReferrerMarker() {
        let query = URLComponents(url: AppLinks.homepage, resolvingAgainstBaseURL: false)?.queryItems

        #expect(query?.first { $0.name == "ref" }?.value == "about")
    }

    @Test("help は GitHub ではなく配布サイト Worker を指す")
    func helpPointsToDistributionSite() {
        #expect(AppLinks.help.host == "befold.degino.com")
    }

    @Test("help は参照元集計のための ref=help を持つ")
    func helpCarriesReferrerMarker() {
        let query = URLComponents(url: AppLinks.help, resolvingAgainstBaseURL: false)?.queryItems

        #expect(query?.first { $0.name == "ref" }?.value == "help")
    }

    @Test("issues は befold リポジトリの Issues ページを指す")
    func issuesPointsToRepositoryIssues() {
        #expect(AppLinks.issues.host == "github.com")
        #expect(AppLinks.issues.path == "/YTommy109/befold/issues")
    }

    @Test("company は開発元のコーポレートサイトを指す")
    func companyPointsToCorporateSite() {
        #expect(AppLinks.company.host == "www.degino.com")
    }

    /// GitHub 側の遷移では ref の内訳を読めないため、印を付けない(TASK-479)。
    @Test("issues は ref パラメータを持たない")
    func issuesCarriesNoReferrerMarker() {
        let query = URLComponents(url: AppLinks.issues, resolvingAgainstBaseURL: false)?.queryItems

        #expect(query == nil)
    }
}
