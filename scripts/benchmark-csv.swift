// 実 WebKit のレイアウト負荷は jsdom で測れないため、通常の CI と分けて手動実行する。
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

let renderOnly = CommandLine.arguments.contains("--render-only")
let arguments = CommandLine.arguments.filter { $0 != "--render-only" }
guard (4 ... 5).contains(arguments.count), ["rendered", "source"].contains(arguments[3]),
      arguments.count == 4 || ["false", "true"].contains(arguments[4])
else { fail("Usage: benchmark-csv Resources CSV rendered|source [false|true (line numbers)] [--render-only]") }
let resources = URL(fileURLWithPath: arguments[1], isDirectory: true)
let fixture = URL(fileURLWithPath: arguments[2])
let mode = arguments[3]
let lineNumbers = arguments.count == 5 && arguments[4] == "true"
let queries = ["s", "sa", "sample", "fixture-absent-xyz", ""]

func read(_ url: URL) -> Data {
    do { return try Data(contentsOf: url) }
    catch { fail("Cannot read \(url.lastPathComponent): \(error)") }
}

func fingerprint(_ data: Data) -> [String: Any] {
    ["bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
}

let fixtureData = read(fixture)
guard let decoded = String(data: fixtureData, encoding: .utf8) else { fail("CSV must be UTF-8") }
let content = decoded.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
let resourceNames = ["viewer.html", "viewer-bundle.js", "style.css", "github-markdown.css", "github.css", "github-dark.css"]
let resourceHashes = Dictionary(uniqueKeysWithValues: resourceNames.map {
    ($0, fingerprint(read(resources.appendingPathComponent($0))))
})
emit([
    "type": "metadata", "mode": mode, "lineNumbers": lineNumbers, "renderOnly": renderOnly,
    "queries": renderOnly ? [] : queries,
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "viewport": ["width": 1200, "height": 800], "zoom": 1,
    "fixture": fingerprint(fixtureData), "normalizedFixture": fingerprint(Data(content.utf8)),
    "resources": resourceHashes, "frameMeasurement": "not-measured-work-only",
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
        window.title = "Befold CSV benchmark — \(mode)"
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
                try await measure("render",
                                  body: "setViewMode(mode); setLineNumbers(lineNumbers); await render(content, 'csv', ',');",
                                  arguments: ["mode": mode, "lineNumbers": lineNumbers, "content": content])
                if !renderOnly {
                    try await measure("open-find", body: "_mmdOpenFind();")
                    for query in queries {
                        try await measure("query:" + query, body: """
                        const input = document.getElementById('mmd-find-input');
                        input.value = query;
                        input.dispatchEvent(new Event('input', {bubbles: true}));
                        """, arguments: ["query": query])
                    }
                }
                emit(["type": "complete"])
                window.orderOut(nil)
                exit(0)
            } catch { fail("Measurement failed: \(error)") }
        }
    }

    @MainActor
    func measure(_ name: String, body: String, arguments: [String: Any] = [:]) async throws {
        let script = #"""
        const start = performance.now();
        \#(body)
        const workMs = performance.now() - start;
        const wrap = document.getElementById('diagram-wrap');
        const layoutStart = performance.now();
        const height = wrap.getBoundingClientRect().height;
        const layoutMs = performance.now() - layoutStart;
        const error = document.getElementById('mmd-error').textContent;
        if (error) throw new Error(error);
        const text = wrap.textContent;
        const rows = wrap.querySelectorAll('tr').length;
        if (!globalThis.__csvBenchmarkSnapshot) {
            const cells = wrap.querySelectorAll('th, td');
            globalThis.__csvBenchmarkSnapshot = {text, rows,
                scopes: cells.length ? Array.from(cells, cell => cell.textContent) : [text]};
        }
        const snapshot = globalThis.__csvBenchmarkSnapshot;
        if (text !== snapshot.text || rows !== snapshot.rows) {
            throw new Error('Search changed rendered text or row count');
        }
        const count = document.getElementById('mmd-find-count').textContent;
        const countParts = count.match(/(\d+)\s*\/\s*(\d+)/);
        const matchCount = countParts ? Number(countParts[2]) : 0;
        const queryText = document.getElementById('mmd-find-input').value;
        const expression = new RegExp(queryText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
        let expectedMatches = 0;
        if (queryText) for (const scope of snapshot.scopes) {
            expression.lastIndex = 0;
            while (expression.exec(scope) !== null) expectedMatches++;
        }
        if (matchCount !== expectedMatches) throw new Error('Search count differs from CSV text');
        const native = globalThis.CSS?.highlights?.get('mmd-find-match');
        const marks = wrap.querySelectorAll('mark.mmd-find-match').length;
        if (native && (native.size > matchCount || marks !== 0)) {
            throw new Error('Native highlights exceed matches or overlap legacy marks');
        }
        return {workMs, layoutMs, frameMs: null, frameMeasurement: 'not-measured-work-only',
            visibility: document.visibilityState, userAgent: navigator.userAgent,
            viewport: {width: innerWidth, height: innerHeight}, height, rows,
            elements: wrap.querySelectorAll('*').length, pathRefs: wrap.querySelectorAll('.befold-path-ref').length,
            textLength: text.length, marks, nativeMatches: native?.size || 0,
            nativeHighlightRegistered: !!native, count, matchCount, expectedMatches};
        """#
        let result: Any? = try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) {
                continuation.resume(with: $0)
            }
        }
        guard let result = result as? [String: Any] else { fail("Missing result for \(name)") }
        emit(["operation": name, "result": result])
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let benchmark = Benchmark()
benchmark.webView.loadFileURL(resources.appendingPathComponent("viewer.html"), allowingReadAccessTo: resources)
DispatchQueue.main.asyncAfter(deadline: .now() + 180) { fail("180 second benchmark timeout") }
app.run()
