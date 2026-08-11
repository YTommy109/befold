// viewer 用 JS の未定義参照を機械検出するための ESLint 設定（TASK-432.2）。
//
// ESM 化では「viewer.js の識別子を viewer-main.js が裸で参照する」形を import へ
// 置き換える。付け忘れた識別子はバンドル時にエラーにならず実行時に初めて落ちるため、
// no-undef を有効にして機械的に検出できる状態を作る（ADR 0005 の Decision）。
//
// 対象は viewer-src/ のソースのみ。ベンダー同梱物（*.min.js）と esbuild 成果物
// （viewer-bundle.js）は検査対象外。

const browserGlobals = {
  window: "readonly",
  document: "readonly",
  globalThis: "readonly",
  console: "readonly",
  navigator: "readonly",
  location: "readonly",
  setTimeout: "readonly",
  clearTimeout: "readonly",
  setInterval: "readonly",
  clearInterval: "readonly",
  requestAnimationFrame: "readonly",
  cancelAnimationFrame: "readonly",
  queueMicrotask: "readonly",
  matchMedia: "readonly",
  getComputedStyle: "readonly",
  CSS: "readonly",
  Element: "readonly",
  HTMLElement: "readonly",
  Node: "readonly",
  NodeFilter: "readonly",
  Range: "readonly",
  Blob: "readonly",
  URL: "readonly",
  TextEncoder: "readonly",
  TextDecoder: "readonly",
  atob: "readonly",
  btoa: "readonly",
  fetch: "readonly",
  MutationObserver: "readonly",
  ResizeObserver: "readonly",
  IntersectionObserver: "readonly",
  DOMParser: "readonly",
  XMLSerializer: "readonly",
  CustomEvent: "readonly",
  Event: "readonly",
  MouseEvent: "readonly",
  KeyboardEvent: "readonly",
  Image: "readonly",
  performance: "readonly",
  webkit: "readonly",
};

// viewer.html が <script> で先に読み込む同梱ベンダー（バンドルに含めない）。
// mermaid は描画の瞬間まで遅延ロードするため、同じくグローバル参照のまま。
const vendorGlobals = {
  markdownit: "readonly",
  hljs: "readonly",
  DOMPurify: "readonly",
  mermaid: "readonly",
};

export default [
  {
    files: ["viewer-src/**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: { ...browserGlobals, ...vendorGlobals },
    },
    linterOptions: {
      reportUnusedDisableDirectives: true,
    },
    rules: {
      // 本設定の目的。裸のグローバル参照の付け忘れをここで落とす。
      "no-undef": "error",
      // import した名前を使っていない＝移行の取りこぼしの兆候。
      "no-unused-vars": ["error", { args: "none", caughtErrors: "none", varsIgnorePattern: "^_" }],
    },
  },
];
