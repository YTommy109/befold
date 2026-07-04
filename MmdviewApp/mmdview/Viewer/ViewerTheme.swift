import AppKit

/// ビューアの「面(キャンバス)」の配色定義。
///
/// キャンバス色はここが唯一の定義。ウィンドウ背景に設定し、WKWebView は透過
/// (drawsBackground=false)、CSS 側も地の色を塗らない(body 透明。style.css
/// 冒頭のコメント参照)ことで、ネイティブ部分と WebView 部分が構成上必ず
/// 同色になる。同じ値を CSS 側に重複定義しないこと。
enum ViewerTheme {
    /// ウィンドウ背景 = コンテンツの地の色。
    /// ライトは白、ダークは WebKit の Canvas 相当の #1E1E1E。
    static let canvas = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1)
            : .white
    }
}
