// viewer の JS をテストから読み込むためのハーネス。
//
// viewer-src/ は関心ごとの ES モジュール群で、公開面は main.js に集約されている
// (TASK-432.2 / TASK-432.3)。ここでは本番と同じ esbuild でモジュールグラフを
// 1 つの IIFE にまとめ、それを jsdom の window.eval で評価する。
//
// require(babel 変換)で読む形にしないのは、モジュール本体が window / document を
// 裸のグローバルとして参照するため。require 経路では Node の globalThis へ
// 結び付けるしかなく、1 つのテストが 2 つの window を同時に扱う場面
// (viewer-main-source-append.test.js の md/code 比較など)で後から読み込んだ側に
// 全インスタンスが引きずられる。window.eval なら評価スコープが window ごとに
// 分かれるため、ブラウザと同じ独立性が保てる。
//
// 評価時に初期化は走らない(_mmdInit() の呼び出しは本番エントリ
// viewer-src/index.js が持ち、テスト用エントリは持たない)。DOM を用意したうえで
// _mmdInit() を呼ぶかどうかは従来どおりテスト側が決める。

const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

const esbuild = require('esbuild');

const RESOURCES_DIR = path.join(__dirname, '..', '..');
// viewer のモジュールソース。コミット済み成果物ではなくソースからバンドルするため、
// ソースを編集した直後もビルドを挟まずにテストが現在の実装を見る。
const VIEWER_SRC_DIR = path.join(RESOURCES_DIR, '..', '..', 'viewer-src');

// テスト用エントリ。本番エントリ(index.js)との違いは 2 点だけ。
// テストが名前で取り出せるよう名前空間を 1 箇所へ置くことと、_mmdInit() を
// 呼ばないこと(初期化タイミングをテストが決められるようにする)。
// 読み込むのは本番と同じ公開面の barrel(main.js)で、グローバルへの露出も同じ
// exposeGlobals を通すため、「テストでは window 経由で見えるが本番では見えない」
// ずれは生じない。
const TEST_ENTRY = [
  "import * as main from './main.js';",
  "import { exposeGlobals } from './expose.js';",
  'exposeGlobals(main);',
  'globalThis.__viewerTestExports = { main };',
].join('\n');

let cachedBundle = null;

// 評価するコードを 1 度だけ生成して使い回す(loadViewerMain は 100 回以上呼ばれる)。
function viewerBundleSource() {
  if (cachedBundle === null) {
    cachedBundle = esbuild.buildSync({
      stdin: { contents: TEST_ENTRY, resolveDir: VIEWER_SRC_DIR, sourcefile: 'test-entry.js' },
      bundle: true,
      format: 'iife',
      target: 'safari17',
      write: false,
    }).outputFiles[0].text;
  }
  return cachedBundle;
}

function readResource(name) {
  return fs.readFileSync(path.join(RESOURCES_DIR, name), 'utf8');
}

// jsdom が実装していない、WKWebView では常に存在する API を補う。
// (未実装のまま _mmdInit() を呼ぶと matchMedia で TypeError になる)
function installBrowserStubs(window) {
  window.matchMedia = function (query) {
    return {
      media: query,
      matches: false,
      addEventListener: function () {},
      removeEventListener: function () {},
    };
  };
  // jsdom はレイアウトを持たないため scrollIntoView が未実装。検索ヒットへの
  // スクロールは副作用のみで戻り値を持たないので、何もしない実装で足りる。
  if (typeof window.Element.prototype.scrollIntoView !== 'function') {
    window.Element.prototype.scrollIntoView = function () {};
  }
  // jsdom は blob URL を実装していない。PDF 表示は blob: URL の生成/解放だけを
  // 行い中身は WebKit の PDF プラグインが描くため、識別可能な擬似 URL で足りる。
  if (typeof window.URL.createObjectURL !== 'function') {
    let issued = 0;
    window.URL.createObjectURL = function () {
      issued += 1;
      return 'blob:https://localhost/stub-' + issued;
    };
    window.URL.revokeObjectURL = function () {};
  }
}

// viewer.html の DOM 上でバンドルを評価し、公開面(main.js)のエクスポートを
// 返す。scripts は実行しない(JSDOM の既定)ため、評価はここで明示的に行う。
//
// options.hostFeatures / options.initialZoom / options.initialFindOptions /
// options.findStrings / options.bannerStrings は Swift 側(ViewerBridge)が
// 注入する window グローバルに対応する。
// options.init が false のときは _mmdInit() を呼ばず、定義だけを読み込む。
function loadViewerMain(options) {
  const opts = options || {};
  // runScripts: 'outside-only' は viewer.html の <script>(= viewer-bundle.js の
  // コミット済み成果物)を実行しない一方で、window.eval をその window の
  // グローバルスコープで動かす。成果物ではなくソースからのバンドルを評価できる。
  const dom = new JSDOM(readResource('viewer.html'), {
    url: 'https://localhost/',
    runScripts: 'outside-only',
  });
  const window = dom.window;

  installBrowserStubs(window);
  if (opts.initialZoom !== undefined) {
    window._mmdInitialZoom = opts.initialZoom;
  }
  if (opts.hostFeatures !== undefined) {
    window._mmdHostFeatures = opts.hostFeatures;
  }
  if (opts.initialFindOptions !== undefined) {
    window._mmdInitialFindOptions = opts.initialFindOptions;
  }
  if (opts.findStrings !== undefined) {
    window._mmdFindStrings = opts.findStrings;
  }
  if (opts.bannerStrings !== undefined) {
    window._mmdBannerStrings = opts.bannerStrings;
  }
  // ベンダー(markdown-it / highlight.js / DOMPurify)はバンドル同梱のため、
  // ここで window へ注入するものは無い(TASK-432.5)。テストは常に本番と同じ
  // 経路(md.render → DOMPurify、hljs 付きのソース表示)を通る。

  // バンドルを評価すると、この window のクロージャ状態(ズームストア等)が作られる。
  window.eval(viewerBundleSource());
  const { main } = window.__viewerTestExports;

  if (opts.init !== false) {
    main._mmdInit();
  }

  return { dom, window, document: window.document, main };
}

// window.webkit.messageHandlers を差し替え、postMessage された内容を記録する。
// 返り値の配列に { name, payload } が push される。
function captureBridgeMessages(window, names) {
  const received = [];
  const handlers = {};
  names.forEach(function (name) {
    handlers[name] = {
      postMessage: function (payload) {
        received.push({ name: name, payload: payload });
      },
    };
  });
  window.webkit = { messageHandlers: handlers };
  return received;
}

// ユーザー操作と同じマウスイベント(e.isTrusted === true)を要素へ流す。
// reference-clicks.js のクリック/contextmenu ハンドラは XSS からの自動発火を防ぐため
// isTrusted のイベントだけを処理するので、これがないと挙動を一切テストできない。
// 公開側の isTrusted は仕様どおり書き換え不可の own プロパティで、さらに
// dispatchEvent() が内部実装オブジェクト(Symbol(impl))の値を false に落とす。
// そこで実装側に「常に true・代入は無視」のアクセサを被せて再現する。
function dispatchTrustedMouseEvent(window, type, element, init) {
  const event = new window.MouseEvent(
    type,
    Object.assign({ bubbles: true, cancelable: true }, init || {}),
  );
  const implSymbol = Object.getOwnPropertySymbols(event).find(
    (symbol) => symbol.description === 'impl',
  );
  Object.defineProperty(event[implSymbol], 'isTrusted', {
    get: function () {
      return true;
    },
    set: function () {},
    configurable: true,
  });
  element.dispatchEvent(event);
  return event;
}

function dispatchTrustedClick(window, element, init) {
  return dispatchTrustedMouseEvent(window, 'click', element, init);
}

function dispatchTrustedContextMenu(window, element, init) {
  return dispatchTrustedMouseEvent(window, 'contextmenu', element, init);
}

module.exports = {
  loadViewerMain,
  captureBridgeMessages,
  readResource,
  dispatchTrustedClick,
  dispatchTrustedContextMenu,
};
