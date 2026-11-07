// 実 WebKit で追記処理を測る任意実行ハーネス。CI の時間閾値には使わない。
import AppKit
import CryptoKit
import WebKit

func emit(_ value: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}

func fail(_ message: String) -> Never {
    emit(["error": message])
    exit(1)
}

func fingerprint(_ data: Data) -> [String: Any] {
    ["bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
}

guard CommandLine.arguments.count == 3, ["mermaid", "paths"].contains(CommandLine.arguments[2]) else {
    fail("Usage: benchmark-markdown-append Resources mermaid|paths")
}

let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let scenario = CommandLine.arguments[2]
let resourceNames = [
    "viewer.html",
    "viewer-bundle.js",
    "mermaid.min.js",
    "style.css",
    "github-markdown.css",
    "github.css",
    "github-dark.css",
]
let resourceHashes = Dictionary(uniqueKeysWithValues: resourceNames.map { name in
    guard let data = try? Data(contentsOf: resources.appendingPathComponent(name)) else {
        fail("Cannot read \(name)")
    }
    return (name, fingerprint(data))
})

/// 小さい追記を繰り返し、既存の図の再ラップだけを切り分ける。ファイル読込は含めない。
let chunks = (0 ..< 20).map { index in
    "## Chapter \(index)\n\n```mermaid\ngraph LR; A\(index)-->B\(index)\n```\n\n"
}

let paragraph = "Paragraph `src/sample.swift` with **bold** text and `inline code`.\n\n"
let initial = scenario == "mermaid" ? chunks[0] : String(repeating: paragraph, count: 15000)
let additions = scenario == "mermaid"
    ? Array(chunks.dropFirst())
    : Array(repeating: String(repeating: paragraph, count: 500), count: 10)
let checks = scenario == "mermaid" ? #"""
const diagrams = [...wrap.querySelectorAll('.mermaid')];
const wrappers = [...wrap.querySelectorAll('.diagram-zoom-wrap')];
const indices = wrappers.map(node => Number(node.dataset.diagramIndex));
const firstPreserved = first.isConnected && first.querySelector('.diagram-zoom-inner').style.zoom === initialZoom;
if (diagrams.length !== 20 || diagrams.some(node => !node.querySelector('svg')) || !firstPreserved) {
    throw new Error('Diagram content or existing zoom changed');
}
return {steps, totalMs: steps.reduce((sum, ms) => sum + ms, 0),
    diagrams: diagrams.length, wrappers: wrappers.length, indices, firstPreserved,
    nestedWrappers: wrap.querySelectorAll('.diagram-zoom-wrap .diagram-zoom-wrap').length,
    userAgent: navigator.userAgent, visibility: document.visibilityState};
"""# : #"""
const paths = wrap.querySelectorAll('.befold-path-ref').length;
const expectedText = 'Paragraph src/sample.swift with bold text and inline code.\n'.repeat(20000);
if (paths !== 20000 || wrap.textContent !== expectedText || !first.isConnected) {
    throw new Error('Appended Markdown text, references or original DOM changed');
}
return {steps, totalMs: steps.reduce((sum, ms) => sum + ms, 0),
    paths, elements: wrap.querySelectorAll('*').length, firstPreserved: first.isConnected,
    html: wrap.innerHTML, text: wrap.textContent,
    userAgent: navigator.userAgent, visibility: document.visibilityState};
"""#

emit([
    "type": "metadata", "scenario": scenario,
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "viewport": ["width": 1200, "height": 800], "zoom": 1,
    "initial": fingerprint(Data(initial.utf8)),
    "additions": additions.map { fingerprint(Data($0.utf8)) },
    "resources": resourceHashes, "frameMeasurement": "not-measured-work-plus-forced-layout",
])

final class Benchmark: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let window: NSWindow

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window._mmdInitialZoom = 1; window._mmdInitialFindOptions = {};",
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: configuration)
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = "Befold Markdown append benchmark"
        window.contentView = webView
        webView.navigationDelegate = self
        window.orderFrontRegardless()
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        fail("Web content process terminated")
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        fail("Navigation failed: \(error)")
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        fail("Navigation failed: \(error)")
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        Task { @MainActor in
            do {
                let result = try await webView.callAsyncJavaScript(
                    #"""
                    setViewMode('rendered');
                    await render(initial, 'md');
                    const wrap = document.getElementById('diagram-wrap');
                    const first = scenario === 'mermaid' ? wrap.querySelector('.diagram-zoom-wrap') : wrap.firstChild;
                    if (scenario === 'mermaid') first.querySelector('.diagram-zoom-in').click();
                    const initialZoom = scenario === 'mermaid' ? first.querySelector('.diagram-zoom-inner').style.zoom : '';
                    void wrap.getBoundingClientRect().height;
                    const steps = [];
                    for (let i = 0; i < additions.length; i++) {
                        // appendChunk は同期 API。新しい図の SVG とラッパーが揃うまで待つ。
                        // MutationObserver は実装内の完了フックや固定 sleep を必要としない。
                        const done = scenario === 'mermaid' ? new Promise(resolve => {
                            const observer = new MutationObserver(() => {
                                const diagrams = wrap.querySelectorAll('.mermaid');
                                const last = diagrams[diagrams.length - 1];
                                if (diagrams.length === i + 2 && last.querySelector('svg') && last.closest('.diagram-zoom-wrap')) {
                                    observer.disconnect();
                                    resolve();
                                }
                            });
                            observer.observe(wrap, {childList: true, subtree: true});
                        }) : null;
                        const start = performance.now();
                        appendChunk(additions[i], 'md');
                        if (done) await done;
                        void wrap.getBoundingClientRect().height;
                        steps.push(performance.now() - start);
                        if (document.getElementById('mmd-error').textContent) throw new Error('Mermaid render failed');
                    }
                    \#(checks)
                    """#,
                    arguments: ["initial": initial, "additions": additions, "scenario": scenario],
                    in: nil,
                    contentWorld: .page
                )
                guard var result = result as? [String: Any] else { fail("Missing benchmark result") }
                for key in ["html", "text"] {
                    if let value = result.removeValue(forKey: key) as? String {
                        result[key + "Fingerprint"] = fingerprint(Data(value.utf8))
                    }
                }
                emit(["type": "result", "result": result])
                emit(["type": "complete"])
                window.orderOut(nil)
                exit(0)
            } catch { fail("Measurement failed: \(error)") }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let benchmark = Benchmark()
benchmark.webView.loadFileURL(resources.appendingPathComponent("viewer.html"), allowingReadAccessTo: resources)
DispatchQueue.main.asyncAfter(deadline: .now() + 180) { fail("180 second benchmark timeout") }
app.run()
