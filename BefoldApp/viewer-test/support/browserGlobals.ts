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
import { JSDOM } from 'jsdom';

const dom = new JSDOM('');

// lib.dom は DOMParser / window を常に在るものとして宣言するが、node 環境の
// Jest では未定義なので、在るかどうかは実行時の値で見る。
const globals: Record<string, unknown> = globalThis;

if (globals.DOMParser === undefined) {
  globals.DOMParser = dom.window.DOMParser;
}
if (globals.window === undefined) {
  globals.window = dom.window;
}
