// viewer-main.js をテストから読み込むためのハーネス。
//
// viewer-main.js は classic script として viewer.html に読み込まれ、viewer.js が
// 定義したグローバル(ZOOM_DEFAULT / parseStoredZoom 等)に依存する。そのため単体の
// require では解決できず、ブラウザと同じ「1つのグローバルスコープへ順に評価する」
// 形を jsdom 上で再現する。viewer-main.js 末尾のエクスポート境界(typeof module
// ガード)により、評価時点では初期化は走らない。DOM を用意したうえで
// _mmdInit() を呼ぶかどうかはテスト側が決める。

const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

const RESOURCES_DIR = path.join(__dirname, '..', '..');

function readResource(name) {
  return fs.readFileSync(path.join(RESOURCES_DIR, name), 'utf8');
}

// jsdom が実装していない、WKWebView では常に存在する API を補う。
// (未実装のまま _mmdInit() を呼ぶと matchMedia で TypeError になる)
function installBrowserStubs(window) {
  window.matchMedia = function(query) {
    return {
      media: query,
      matches: false,
      addEventListener: function() {},
      removeEventListener: function() {},
    };
  };
}

// viewer.html の DOM 上に viewer.js → viewer-main.js を評価し、両者の
// エクスポートを返す。scripts は実行しない(JSDOM の既定)ため、評価順は
// ここで明示する。
//
// options.hostFeatures / options.initialZoom / options.initialFindOptions /
// options.findStrings / options.bannerStrings は Swift 側(ViewerBridge)が
// 注入する window グローバルに対応する。
// options.init が false のときは _mmdInit() を呼ばず、定義だけを読み込む。
function loadViewerMain(options) {
  const opts = options || {};
  // runScripts: 'outside-only' は <script> タグを実行しない一方で、window.eval を
  // jsdom 側のグローバルスコープで動かす。ブラウザと同じ「1つのグローバルへ順に
  // 評価する」形を、viewer.html 内のベンダー script を読み込まずに再現できる。
  const dom = new JSDOM(readResource('viewer.html'), {
    url: 'https://localhost/',
    runScripts: 'outside-only',
  });
  const window = dom.window;

  installBrowserStubs(window);
  if (opts.initialZoom !== undefined) { window._mmdInitialZoom = opts.initialZoom; }
  if (opts.hostFeatures !== undefined) { window._mmdHostFeatures = opts.hostFeatures; }
  if (opts.initialFindOptions !== undefined) { window._mmdInitialFindOptions = opts.initialFindOptions; }
  if (opts.findStrings !== undefined) { window._mmdFindStrings = opts.findStrings; }
  if (opts.bannerStrings !== undefined) { window._mmdBannerStrings = opts.bannerStrings; }

  // module を window 上に置くことでエクスポート境界を有効にする。両ファイルが
  // 同じ module を共有しないよう、評価ごとに差し替えて回収する。
  function evaluate(name) {
    window.module = { exports: {} };
    window.eval(readResource(name));
    const exported = window.module.exports;
    delete window.module;
    return exported;
  }

  const viewer = evaluate('viewer.js');
  const main = evaluate('viewer-main.js');

  if (opts.init !== false) { main._mmdInit(); }

  return { dom, window, document: window.document, viewer, main };
}

// window.webkit.messageHandlers を差し替え、postMessage された内容を記録する。
// 返り値の配列に { name, payload } が push される。
function captureBridgeMessages(window, names) {
  const received = [];
  const handlers = {};
  names.forEach(function(name) {
    handlers[name] = {
      postMessage: function(payload) { received.push({ name: name, payload: payload }); },
    };
  });
  window.webkit = { messageHandlers: handlers };
  return received;
}

module.exports = { loadViewerMain, captureBridgeMessages, readResource };
