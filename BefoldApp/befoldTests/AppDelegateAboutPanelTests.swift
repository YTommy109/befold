// BefoldApp/befoldTests/AppDelegateAboutPanelTests.swift
import Foundation
import Testing

@Suite
struct AppDelegateAboutPanelTests {
    @Test("AboutパネルがTommy109表記とGitHubプロフィールリンクを含む")
    func aboutPanelUsesTommy109Branding() throws {
        let source = try String(contentsOf: appDelegateURL(), encoding: .utf8)

        #expect(source.contains("\"Tommy109\""))
        #expect(source.contains("https://github.com/YTommy109"))
        #expect(!source.contains("Degino Inc."))
        #expect(!source.contains("https://www.degino.com/"))
    }

    private func appDelegateURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // befoldTests
            .deletingLastPathComponent() // BefoldApp
            .appendingPathComponent("befold/App/AppDelegate.swift")
    }
}
