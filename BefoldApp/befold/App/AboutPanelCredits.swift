import AppKit

/// About パネルの credits(著作権表記)を組み立てる純粋ロジック。
enum AboutPanelCredits {
    static func make(font: NSFont) -> NSAttributedString {
        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(
            string: "befold",
            attributes: [.link: URL(string: "https://ytommy109.github.io/befold/") as Any, .font: font]
        ))
        credits.append(NSAttributedString(string: "\nCopyright © 2026 ", attributes: [.font: font]))
        credits.append(NSAttributedString(
            string: "Tommy109",
            attributes: [.link: URL(string: "https://github.com/YTommy109") as Any, .font: font]
        ))
        credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
        return credits
    }
}
