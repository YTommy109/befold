// viewer.html の WKWebView スモークテスト。
//
// GUI を目視せずに、実アプリと同じ loadFileURL(allowingReadAccessTo:) 経路で
// viewer.html を読み込み、以下を自動検証する（テスト規約で WebView 層は
// 自動テスト対象外のため、CSP や viewer.html を触ったときの回帰確認に使う）:
//   1. CSP 下でローカルスクリプト（viewer.js / mermaid / markdown-it）がロードされる
//   2. .mmd が mermaid で SVG 描画される
//   3. .md が markdown-it で描画される
//   4. 外部画像による情報流出が CSP(img-src) でブロックされる
//
// 使い方: swift scripts/webview-smoke.swift [Resources ディレクトリ]
//   省略時は BefoldApp/befold/Resources を対象にする。
// 成功で exit 0 / 失敗で非 0。

import AppKit
import WebKit

let resourceDir = URL(
    fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "BefoldApp/befold/Resources",
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
    func checkScriptsLoaded() {
        webView.evaluateJavaScript(
            "[typeof markdownit, typeof mermaid, typeof ZOOM_DEFAULT, typeof md].join(',')"
        ) { result, error in
            if let error { self.fail("script-load: \(error)") }
            guard let s = result as? String else { self.fail("script-load: no result") }
            print("globals: \(s)")
            if s != "function,object,number,object" {
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
            self.checkExfilBlocked()
        }
    }

    // 4. 外部画像による流出が CSP(img-src) でブロックされるか
    func checkExfilBlocked() {
        let payload = "<img src=\"https://example.com/exfil.png\" "
            + "onload=\"window.__exfil='LOADED'\" onerror=\"window.__exfil='BLOCKED'\">"
        let doc = "before\n\n\(payload)\n\nafter"
        asyncJS(
            "window.__exfil='PENDING'; await render(\(jsString(doc)), 'md'); "
                + "await new Promise(r => setTimeout(r, 800)); return window.__exfil;",
            "exfil"
        ) { r in
            print("exfil img result: \(String(describing: r))")
            if (r as? String) == "LOADED" {
                self.fail("外部画像がロードされた（img-src が効いていない）")
            }
            self.checkDataFrameBlocked()
        }
    }

    // 5. Markdown 内に静的に書かれた data: iframe が CSP(frame-src) でブロックされるか
    //    (frame-src は blob: のみ許可。PDF 表示はスクリプト生成の blob URL を使う)
    func checkDataFrameBlocked() {
        let payload = "<iframe src=\"data:text/html;base64,PGgxPng8L2gxPg==\"></iframe>"
        let doc = "before\n\n\(payload)\n\nafter"
        asyncJS(
            "window.__frameViolation = null; "
                + "document.addEventListener('securitypolicyviolation', "
                + "function(e) { window.__frameViolation = e.violatedDirective; }); "
                + "await render(\(jsString(doc)), 'md'); "
                + "await new Promise(r => setTimeout(r, 800)); return window.__frameViolation;",
            "data-frame"
        ) { r in
            print("data: iframe violation: \(String(describing: r))")
            guard let directive = r as? String,
                  directive.hasPrefix("frame-src") || directive.hasPrefix("child-src") else {
                self.fail("data: iframe が CSP でブロックされなかった")
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
