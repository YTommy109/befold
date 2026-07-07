import AppKit
@testable import befold
import Foundation
import Testing

@Suite
struct AboutPanelCreditsTests {
    @Test("Tommy109がGitHubプロフィールへのリンク付きで含まれる")
    func creditsLinkToGitHubProfile() {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        let credits = AboutPanelCredits.make(font: font)

        let fullString = credits.string
        #expect(fullString.contains("Tommy109"))
        #expect(!fullString.contains("Degino"))
        let range = (fullString as NSString).range(of: "Tommy109")
        let link = credits.attribute(.link, at: range.location, effectiveRange: nil) as? URL
        #expect(link == URL(string: "https://github.com/YTommy109"))
    }
}
