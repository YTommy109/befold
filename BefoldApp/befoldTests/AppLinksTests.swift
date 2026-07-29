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
        #expect(AppLinks.homepage.host == "befold.tommy109.workers.dev")
    }

    @Test("homepage は参照元集計のための ref=about を持つ")
    func homepageCarriesReferrerMarker() {
        let query = URLComponents(url: AppLinks.homepage, resolvingAgainstBaseURL: false)?.queryItems

        #expect(query?.first { $0.name == "ref" }?.value == "about")
    }
}
