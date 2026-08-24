// viewer.html の WKWebView スモークテスト。
//
// GUI を目視せずに、実アプリと同じ loadFileURL(allowingReadAccessTo:) 経路で
// viewer.html を読み込み、以下を自動検証する（テスト規約で WebView 層は
// 自動テスト対象外のため、CSP や viewer.html を触ったときの回帰確認に使う）:
//   1. CSP 下でローカルスクリプト（viewer-bundle.js / mermaid / markdown-it）がロードされる
//   2. .mmd が mermaid で SVG 描画される
//   3. .md が markdown-it で描画される
//   4. 外部画像による情報流出が CSP(img-src) でブロックされる
//
// 使い方: swift scripts/webview-smoke.swift [Resources ディレクトリ]
//   省略時は BefoldApp/BefoldKit/Resources を対象にする。
// 成功で exit 0 / 失敗で非 0。

import AppKit
import WebKit

let resourceDir = URL(
    fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "BefoldApp/BefoldKit/Resources",
    isDirectory: true
)
let htmlURL = resourceDir.appendingPathComponent("viewer.html")

final class SmokeRunner: NSObject, WKNavigationDelegate {
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        // 実アプリと同じく初期倍率を注入する
        let zoom = WKUserScript(
            source: "window._mmdInitialZoom = 1.0;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(zoom)
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: config
        )
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkScriptsLoaded()
    }

    func fail(_ msg: String) -> Never {
        print("FAIL: \(msg)")
        exit(1)
    }

    // async JS を await して結果を取得する
    func asyncJS(_ body: String, _ label: String, _ cont: @escaping (Any?) -> Void) {
        webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case let .success(value): cont(value)
            case let .failure(error): self.fail("\(label): JS error \(error)")
            }
        }
    }

    func jsString(_ s: String) -> String {
        String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
    }

    // 1. CSP 下でローカルスクリプトがロードされたか
    // mermaid.min.js は TASK-1.10 で mermaid 使用時のみ動的 <script> 挿入で遅延ロードする
    // ようになったため、ここでは typeof mermaid を確認しない(未ロードで 'undefined' が
    // 正しい)。実際にロードされることは checkMermaid() の描画確認で検証する。
    // markdown-it / highlight.js / DOMPurify も TASK-432.5 で viewer-bundle.js の
    // 中へ入ったため、グローバル(markdownit / hljs)としては見えない。ここでは
    // 公開関数 render と定数がグローバルへ載っていること = バンドルの評価と公開が
    // 通ったことだけを確認する。ベンダーが実際に動くことは、この後の
    // checkMarkdown()(markdown-it + DOMPurify)と checkHighlight()(highlight.js)の
    // 描画確認が担う。
    func checkScriptsLoaded() {
        webView.evaluateJavaScript(
            "[typeof ZOOM_DEFAULT, typeof render].join(',')"
        ) { result, error in
            if let error { self.fail("script-load: \(error)") }
            guard let s = result as? String else { self.fail("script-load: no result") }
            print("globals: \(s)")
            if s != "number,function" {
                self.fail("ローカルスクリプトが CSP でブロックされた可能性: \(s)")
            }
            self.checkMermaid()
        }
    }

    // 2. .mmd 描画
    func checkMermaid() {
        let mmd = "graph TD; A-->B"
        asyncJS(
            "await render(\(jsString(mmd)), 'mmd'); "
                + "return document.querySelector('#diagram-wrap svg') ? 'svg' : 'nosvg';",
            "mmd-render"
        ) { r in
            print("mmd render: \(String(describing: r))")
            if (r as? String) != "svg" { self.fail("mermaid が描画されなかった") }
            self.checkMarkdown()
        }
    }

    // 3. .md 描画
    func checkMarkdown() {
        let md = "# Title\n\nHello **world**"
        asyncJS(
            "await render(\(jsString(md)), 'md'); "
                + "var h = document.querySelector('#diagram-wrap h1'); "
                + "return h ? h.textContent : 'noh1';",
            "md-render"
        ) { r in
            print("md render h1: \(String(describing: r))")
            if (r as? String) != "Title" { self.fail("markdown が描画されなかった") }
            self.checkHighlight()
        }
    }

    // 3.2. ソース表示のシンタックスハイライト
    // highlight.js は TASK-432.5 でバンドル同梱になった。グローバル hljs を
    // 見る形では確認できないため、実際にハイライト済みの span が出るかで見る。
    func checkHighlight() {
        asyncJS(
            "await render('let x = 1', 'code', 'swift'); "
                + "return document.querySelector('#diagram-wrap .hljs-keyword') ? 'hl' : 'nohl';",
            "highlight"
        ) { r in
            print("highlight: \(String(describing: r))")
            if (r as? String) != "hl" { self.fail("highlight.js のハイライトが出なかった") }
            self.checkEmbeddedDataImageRenders()
        }
    }

    // 3.5. Markdown 埋め込みの data: URI 画像が CSP(img-src data:) 下で描画されるか
    //      (ローカル画像は MarkdownImageEmbedder が data URI 化してから render に渡す)
    func checkEmbeddedDataImageRenders() {
        let png1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ"
            + "AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let doc = "![dot](data:image/png;base64,\(png1x1))"
        asyncJS(
            "await render(\(jsString(doc)), 'md'); "
                + "var img = document.querySelector('#diagram-wrap img'); "
                + "if (!img) return 'noimg'; "
                + "await img.decode(); return img.naturalWidth;",
            "data-image"
        ) { r in
            print("embedded data image naturalWidth: \(String(describing: r))")
            if (r as? Int) != 1 {
                self.fail("data: URI 画像が markdown 内で描画されなかった")
            }
            self.checkEmbeddedDataImageInInlineHTMLRenders()
        }
    }

    // 3.6. inline HTML の <img> に入れた data: URI 画像が描画されるか(TASK-524)
    //      markdown 記法の data URI は markdown-it の validateLink が通すが、生 HTML は
    //      そこを通らず DOMPurify と CSP だけで決まる。MarkdownImageEmbedder が
    //      <img src> を差し替えても、この経路が塞がっていれば画像は出ない。
    //      幅指定・中央寄せ(GitHub 向け README が使う形)を付けた状態で確認する。
    func checkEmbeddedDataImageInInlineHTMLRenders() {
        let png1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ"
            + "AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let doc = "<p align=\"center\"><img src=\"data:image/png;base64,\(png1x1)\" "
            + "alt=\"dot\" width=\"380\"></p>"
        asyncJS(
            "await render(\(jsString(doc)), 'md'); "
                + "var img = document.querySelector('#diagram-wrap img'); "
                + "if (!img) return 'noimg'; "
                + "await img.decode(); return img.naturalWidth;",
            "data-image-inline-html"
        ) { r in
            print("inline html data image naturalWidth: \(String(describing: r))")
            if (r as? Int) != 1 {
                self.fail("data: URI 画像が inline HTML の <img> で描画されなかった")
            }
            self.checkLargeNonASCIIDocumentRenders()
        }
    }

    // 3.7. 非 ASCII を含む長い <img> タグを持つ文書が現実的な時間で描画されるか(TASK-548)
    //      viewer 側が HTML 全体に正規表現を当てる形へ戻ると、JSC は 16bit 文字列の
    //      バックトラックを解釈実行し、この入力で数十秒〜数分返らなくなる(本文が
    //      空白のまま固まる)。JS 例外は出ないので、検出できるのは所要時間だけ。
    //      実測: 修正後は 10ms 未満、修正前は 6 秒前後(alt 96,000 文字)。3 秒を境にする。
    func checkLargeNonASCIIDocumentRenders() {
        let png1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ"
            + "AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        // 長さは <img> タグ 1 つの中に置く(退行時の停止は 1 タグ内の後戻りで起きる)。
        // 非 ASCII を 1 文字混ぜることが引き金で、全 ASCII の同じ長さでは再現しない。
        let longAlt = "図" + String(repeating: "a", count: 96000)
        let doc = "<img src=\"data:image/png;base64,\(png1x1)\" alt=\"\(longAlt)\">"
        let started = Date()
        asyncJS(
            "await render(\(jsString(doc)), 'md'); "
                + "var img = document.querySelector('#diagram-wrap img'); "
                + "if (!img) return 'noimg'; "
                + "await img.decode(); return img.naturalWidth;",
            "large-non-ascii"
        ) { r in
            let elapsed = Date().timeIntervalSince(started)
            print("large non-ASCII doc naturalWidth: \(String(describing: r)) in \(Int(elapsed * 1000))ms")
            if (r as? Int) != 1 {
                self.fail("非 ASCII を含む長い <img> の文書が描画されなかった")
            }
            if elapsed > 3 {
                self.fail("非 ASCII を含む長い <img> の描画に \(Int(elapsed))s かかった(退行)")
            }
            self.checkExfilBlocked()
        }
    }

    // 4. 外部画像による流出がブロックされるか(TASK-526)
    //
    //    判定は naturalWidth で行う。ここは「画像バイトが取得されたか」を直接測る唯一の
    //    指標で、守りたい対象と一致する。以前は <img onload=/onerror=> の発火を見ていたが、
    //    インラインイベントハンドラは script-src 'self'('unsafe-inline' 無し)で実行自体が
    //    ブロックされるため、**画像が読み込まれても結果は PENDING のまま**だった。
    //    LOADED のときだけ落とす判定だったので、実際に取得できていても通っていた。
    //
    //    実在するホストを使う。到達できない URL では、遮断が効いていなくても
    //    naturalWidth = 0 になり、テストが常に緑になってしまう(測るものと守るものの不一致)。
    func checkExfilBlocked() {
        let remoteURL = "https://img.shields.io/badge/license-MIT-blue"
        let doc = "before\n\n<img src=\"\(remoteURL)\" alt=\"badge\">\n\nafter"
        asyncJS(
            "await render(\(jsString(doc)), 'md'); "
                + "await new Promise(r => setTimeout(r, 2500)); "
                + "var img = document.querySelector('#diagram-wrap img'); "
                + "return { hasImg: !!img, "
                + "naturalWidth: img ? img.naturalWidth : -1, "
                + "hasPlaceholder: "
                + "!!document.querySelector('#diagram-wrap .mmd-blocked-image') };",
            "exfil"
        ) { r in
            print("exfil img result: \(String(describing: r))")
            guard let result = r as? [String: Any] else {
                self.fail("外部画像の検証結果を取得できなかった")
            }
            let naturalWidth = (result["naturalWidth"] as? Int) ?? -1
            if naturalWidth > 0 {
                self.fail("外部画像が実際に取得された(naturalWidth=\(naturalWidth))")
            }
            // 一次防御(viewer 側の replaceRemoteImages)が働いていれば <img> は残らず、
            // 代替表示へ置き換わっている。二次防御(RemoteLoadBlocker)だけが効いた場合は
            // <img> が naturalWidth 0 で残る。どちらでも取得は起きていないが、
            // 一次防御が外れたことに気づけるようここで区別する。
            let hasPlaceholder = (result["hasPlaceholder"] as? Bool) ?? false
            if !hasPlaceholder {
                self.fail("リモート画像が代替表示へ置き換わっていない")
            }
            self.checkDataFrameBlocked()
        }
    }

    // 5. Markdown 内に静的に書かれた data: iframe がブロックされるか
    //    多層防御: DOMPurify(既定設定)は <iframe> をタグごと除去するため、まずそれで
    //    到達しないことを確認する。除去されなかった場合の保険として CSP(frame-src、
    //    blob: のみ許可。PDF 表示はスクリプト生成の blob URL を使う)も確認する。
    func checkDataFrameBlocked() {
        let payload = "<iframe src=\"data:text/html;base64,PGgxPng8L2gxPg==\"></iframe>"
        let doc = "before\n\n\(payload)\n\nafter"
        asyncJS(
            "window.__frameViolation = null; "
                + "document.addEventListener('securitypolicyviolation', "
                + "function(e) { window.__frameViolation = e.violatedDirective; }); "
                + "await render(\(jsString(doc)), 'md'); "
                + "await new Promise(r => setTimeout(r, 800)); "
                + "return { violation: window.__frameViolation, "
                + "hasIframe: !!document.querySelector('#diagram-wrap iframe') };",
            "data-frame"
        ) { r in
            print("data: iframe result: \(String(describing: r))")
            guard let result = r as? [String: Any] else {
                self.fail("data: iframe の検証結果を取得できなかった")
            }
            let hasIframe = (result["hasIframe"] as? Bool) ?? true
            if !hasIframe {
                // DOMPurify が <iframe> ごと除去した(sanitizer 層で防御達成)。
                self.checkPdfBlobRenders()
                return
            }
            guard let directive = result["violation"] as? String,
                  directive.hasPrefix("frame-src") || directive.hasPrefix("child-src") else {
                self.fail("data: iframe が sanitizer にも CSP にもブロックされなかった")
            }
            self.checkPdfBlobRenders()
        }
    }

    // 6. PDF が blob: URL の iframe として生成されるか
    func checkPdfBlobRenders() {
        let pdfBase64 = Data("%PDF-1.4\n%%EOF".utf8).base64EncodedString()
        asyncJS(
            "await render(\(jsString(pdfBase64)), 'pdf'); "
                + "var f = document.querySelector('#diagram-wrap iframe'); "
                + "return f ? f.src.slice(0, 5) : 'noframe';",
            "pdf-render"
        ) { r in
            print("pdf iframe src scheme: \(String(describing: r))")
            if (r as? String) != "blob:" {
                self.fail("PDF iframe が blob: URL で生成されなかった")
            }
            print("PASS: CSP 下で全スクリプト稼働・mmd/md 描画・外部画像/data: iframe ブロック・PDF blob 表示を確認")
            exit(0)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let runner = SmokeRunner()
runner.webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)

DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
    print("FAIL: timeout")
    exit(2)
}
app.run()
