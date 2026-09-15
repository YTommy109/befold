// viewer の JS をテストから読み込むためのハーネス。
//
// viewer-src/ は関心ごとの ES モジュール群で、公開面は main.ts に集約されている
// (TASK-432.2 / TASK-432.3)。ここでは本番と同じ esbuild でモジュールグラフを
// 1 つの IIFE にまとめ、それを jsdom の window.eval で評価する。
//
// require(babel 変換)で読む形にしないのは、モジュール本体が window / document を
// 裸のグローバルとして参照するため。require 経路では Node の globalThis へ
// 結び付けるしかなく、1 つのテストが 2 つの window を同時に扱う場面
// (viewer-main-source-append.test の md/code 比較など)で後から読み込んだ側に
// 全インスタンスが引きずられる。window.eval なら評価スコープが window ごとに
// 分かれるため、ブラウザと同じ独立性が保てる。
//
// 評価時に初期化は走らない(_mmdInit() の呼び出しは本番エントリ
// viewer-src/index.ts が持ち、テスト用エントリは持たない)。DOM を用意したうえで
// _mmdInit() を呼ぶかどうかは従来どおりテスト側が決める。

import * as fs from 'node:fs';
import * as path from 'node:path';

import * as esbuild from 'esbuild';
import { JSDOM, type DOMWindow } from 'jsdom';

import type * as ViewerMain from '../../viewer-src/main.js';

const RESOURCES_DIR = path.join(__dirname, '..', '..', 'BefoldKit', 'Resources');
// viewer のモジュールソース。コミット済み成果物ではなくソースからバンドルするため、
// ソースを編集した直後もビルドを挟まずにテストが現在の実装を見る。
const VIEWER_SRC_DIR = path.join(__dirname, '..', '..', 'viewer-src');

// テスト用エントリ。本番エントリ(index.ts)との違いは 2 点だけ。
// テストが名前で取り出せるよう名前空間を 1 箇所へ置くことと、_mmdInit() を
// 呼ばないこと(初期化タイミングをテストが決められるようにする)。
// 読み込むのは本番と同じ公開面の barrel(main.ts)で、グローバルへの露出も同じ
// exposeGlobals を通すため、「テストでは window 経由で見えるが本番では見えない」
// ずれは生じない。
const TEST_ENTRY = [
  "import * as main from './main.js';",
  "import { exposeGlobals } from './expose.js';",
  'exposeGlobals(main);',
  'globalThis.__viewerTestExports = { main };',
].join('\n');

let cachedBundle: string | null = null;

// 評価するコードを 1 度だけ生成して使い回す(loadViewerMain は 100 回以上呼ばれる)。
function viewerBundleSource(): string {
  if (cachedBundle === null) {
    const [output] = esbuild.buildSync({
      stdin: { contents: TEST_ENTRY, resolveDir: VIEWER_SRC_DIR, sourcefile: 'test-entry.js' },
      bundle: true,
      format: 'iife',
      target: 'safari17',
      write: false,
    }).outputFiles;
    if (output === undefined) {
      throw new Error('esbuild がテスト用バンドルを出力しなかった');
    }
    cachedBundle = output.text;
  }
  return cachedBundle;
}

export function readResource(name: string): string {
  return fs.readFileSync(path.join(RESOURCES_DIR, name), 'utf8');
}

// jsdom が実装していない、WKWebView では常に存在する API を補う。
// (未実装のまま _mmdInit() を呼ぶと matchMedia で TypeError になる)
function installBrowserStubs(window: DOMWindow): void {
  // viewer が触るのは matches と change の購読だけなので、MediaQueryList の
  // 残り(onchange / addListener など)は持たせない。
  window.matchMedia = (query: string) =>
    ({
      media: query,
      matches: false,
      addEventListener: () => {},
      removeEventListener: () => {},
    }) as unknown as MediaQueryList;
  // jsdom はレイアウトを持たないため scrollIntoView が未実装。検索ヒットへの
  // スクロールは副作用のみで戻り値を持たないので、何もしない実装で足りる。
  if (typeof window.Element.prototype.scrollIntoView !== 'function') {
    window.Element.prototype.scrollIntoView = () => {};
  }
  // jsdom は blob URL を実装していない。PDF 表示は blob: URL の生成/解放だけを
  // 行い中身は WebKit の PDF プラグインが描くため、識別可能な擬似 URL で足りる。
  if (typeof window.URL.createObjectURL !== 'function') {
    let issued = 0;
    window.URL.createObjectURL = () => {
      issued += 1;
      return 'blob:https://localhost/stub-' + issued;
    };
    window.URL.revokeObjectURL = () => {};
  }
}

// Swift 側(ViewerBridge)が注入する window グローバルに対応する。型は
// viewer-src/viewer-globals.d.ts の宣言をそのまま引く(注入値の単一情報源)。
export interface LoadViewerMainOptions {
  // false のときは _mmdInit() を呼ばず、定義だけを読み込む。
  init?: boolean;
  initialZoom?: Window['_mmdInitialZoom'];
  hostFeatures?: Window['_mmdHostFeatures'];
  initialFindOptions?: Window['_mmdInitialFindOptions'];
  findStrings?: Window['_mmdFindStrings'];
  // 見出しジャンプで目印にするレベルの保存値（["h1","h2","h3"] 形式）。
  // 空配列は「3 つとも OFF」で、未指定（プロパティ自体が無い）とは別の意味。
  initialJumpLevels?: Window['_mmdInitialJumpLevels'];
  bannerStrings?: Window['_mmdBannerStrings'];
}

export interface LoadedViewer {
  dom: JSDOM;
  window: DOMWindow;
  document: Document;
  // 公開面(main.ts)の型。window 経由で取り出すため実行時の値は any だが、
  // ここで barrel の型を付けておくことで、存在しない関数の呼び出しや
  // 引数の取り違えがテスト側で型エラーになる。
  main: typeof ViewerMain;
}

// viewer.html の DOM 上でバンドルを評価し、公開面(main.ts)のエクスポートを
// 返す。scripts は実行しない(JSDOM の既定)ため、評価はここで明示的に行う。
export function loadViewerMain(options: LoadViewerMainOptions = {}): LoadedViewer {
  // runScripts: 'outside-only' は viewer.html の <script>(= viewer-bundle.js の
  // コミット済み成果物)を実行しない一方で、window.eval をその window の
  // グローバルスコープで動かす。成果物ではなくソースからのバンドルを評価できる。
  const dom = new JSDOM(readResource('viewer.html'), {
    url: 'https://localhost/',
    runScripts: 'outside-only',
  });
  const window = dom.window;

  installBrowserStubs(window);
  if (options.initialZoom !== undefined) {
    window._mmdInitialZoom = options.initialZoom;
  }
  if (options.hostFeatures !== undefined) {
    window._mmdHostFeatures = options.hostFeatures;
  }
  if (options.initialFindOptions !== undefined) {
    window._mmdInitialFindOptions = options.initialFindOptions;
  }
  if (options.findStrings !== undefined) {
    window._mmdFindStrings = options.findStrings;
  }
  if (options.initialJumpLevels !== undefined) {
    window._mmdInitialJumpLevels = options.initialJumpLevels;
  }
  if (options.bannerStrings !== undefined) {
    window._mmdBannerStrings = options.bannerStrings;
  }
  // ベンダー(markdown-it / highlight.js / DOMPurify)はバンドル同梱のため、
  // ここで window へ注入するものは無い(TASK-432.5)。テストは常に本番と同じ
  // 経路(md.render → DOMPurify、hljs 付きのソース表示)を通る。

  // バンドルを評価すると、この window のクロージャ状態(ズームストア等)が作られる。
  window.eval(viewerBundleSource());
  const { main } = window.__viewerTestExports as { main: typeof ViewerMain };

  if (options.init !== false) {
    main._mmdInit();
  }

  return { dom, window, document: window.document, main };
}

export interface CapturedBridgeMessage {
  name: string;
  payload: unknown;
}

// window.webkit.messageHandlers を差し替え、postMessage された内容を記録する。
// 返り値の配列に { name, payload } が push される。
export function captureBridgeMessages(
  window: DOMWindow,
  names: readonly string[],
): CapturedBridgeMessage[] {
  const received: CapturedBridgeMessage[] = [];
  const handlers: WebKitMessageHandlers = {};
  for (const name of names) {
    handlers[name] = {
      postMessage: (payload) => {
        received.push({ name, payload });
      },
    };
  }
  window.webkit = { messageHandlers: handlers };
  return received;
}

// ユーザー操作と同じマウスイベント(e.isTrusted === true)を要素へ流す。
// reference-clicks.ts のクリック/contextmenu ハンドラは XSS からの自動発火を防ぐため
// isTrusted のイベントだけを処理するので、これがないと挙動を一切テストできない。
// 公開側の isTrusted は仕様どおり書き換え不可の own プロパティで、さらに
// dispatchEvent() が内部実装オブジェクト(Symbol(impl))の値を false に落とす。
// そこで実装側に「常に true・代入は無視」のアクセサを被せて再現する。
function dispatchTrustedMouseEvent(
  window: DOMWindow,
  type: string,
  element: Element,
  init?: MouseEventInit,
): MouseEvent {
  const event = new window.MouseEvent(type, { bubbles: true, cancelable: true, ...init });
  const implSymbol = Object.getOwnPropertySymbols(event).find(
    (symbol) => symbol.description === 'impl',
  );
  if (implSymbol === undefined) {
    throw new Error('jsdom の MouseEvent に内部実装(Symbol(impl))が見つからない');
  }
  const impl: unknown = Reflect.get(event, implSymbol);
  if (typeof impl !== 'object' || impl === null) {
    throw new Error('jsdom の MouseEvent の内部実装がオブジェクトではない');
  }
  Object.defineProperty(impl, 'isTrusted', {
    get: () => true,
    set: () => {},
    configurable: true,
  });
  element.dispatchEvent(event);
  return event;
}

export function dispatchTrustedClick(
  window: DOMWindow,
  element: Element,
  init?: MouseEventInit,
): MouseEvent {
  return dispatchTrustedMouseEvent(window, 'click', element, init);
}

export function dispatchTrustedContextMenu(
  window: DOMWindow,
  element: Element,
  init?: MouseEventInit,
): MouseEvent {
  return dispatchTrustedMouseEvent(window, 'contextmenu', element, init);
}
