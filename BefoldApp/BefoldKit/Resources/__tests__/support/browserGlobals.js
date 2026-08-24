// node 環境の Jest に、viewer-src が本番(WKWebView)で前提とするブラウザ
// グローバルを最小限だけ用意する（TASK-548）。
//
// replaceRemoteImages は当たり付けの正規表現をやめて常に DOMParser を通すように
// なったため、sanitizeRenderedHtml を呼ぶすべてのテストが DOMParser を必要とする。
// 各テストファイルで用意する形にすると、新しいテストを足したときだけ
// `DOMParser is not defined` で落ちる。ここへ集約して全 suite で同じ前提にする。
//
// 既に定義されている場合は上書きしない。viewerMainHarness は suite ごとに専用の
// jsdom window を作って window.eval で評価するため、ここの値には依存しない。
const { JSDOM } = require('jsdom');

const dom = new JSDOM('');

if (global.DOMParser === undefined) {
  global.DOMParser = dom.window.DOMParser;
}
if (global.window === undefined) {
  global.window = dom.window;
}
