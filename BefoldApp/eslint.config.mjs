// viewer 用 JS の未定義参照を機械検出するための ESLint 設定（TASK-432.2）。
//
// ESM 化では「viewer.js の識別子を viewer-main.js が裸で参照する」形を import へ
// 置き換える。付け忘れた識別子はバンドル時にエラーにならず実行時に初めて落ちるため、
// no-undef を有効にして機械的に検出できる状態を作る（ADR 0005 の Decision）。
//
// 対象は viewer-src/ のソースのみ。ベンダー同梱物（*.min.js）と esbuild 成果物
// （viewer-bundle.js）は検査対象外。
//
// TypeScript への段階移行（TASK-432.4）に合わせて .ts も対象にしてある。
// files を .js のままにすると、移行したモジュールが「エラー 0 件」を出しながら
// 実際には 1 度も検査されない状態になり、対象 0 件と合格が区別できない。
// npm script 側も `eslint viewer-src` ではなく拡張子を明示した glob にしてある。
import tseslint from "typescript-eslint";

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

const unusedVarsOptions = { args: "none", caughtErrors: "none", varsIgnorePattern: "^_" };

export default [
  {
    files: ["viewer-src/**/*.{js,ts}"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: { ...browserGlobals, ...vendorGlobals },
    },
    linterOptions: {
      reportUnusedDisableDirectives: true,
    },
  },
  {
    files: ["viewer-src/**/*.js"],
    rules: {
      // 本設定の目的。裸のグローバル参照の付け忘れをここで落とす。
      "no-undef": "error",
      // import した名前を使っていない＝移行の取りこぼしの兆候。
      "no-unused-vars": ["error", unusedVarsOptions],
    },
  },
  {
    files: ["viewer-src/**/*.ts"],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { ecmaVersion: 2022, sourceType: "module" },
    },
    plugins: { "@typescript-eslint": tseslint.plugin },
    rules: {
      // .ts では no-undef を使わない。未定義参照は tsc（npm run typecheck:viewer）が
      // 型として捕まえるほうが正確で、eslint 側は型宣言を未定義と誤検知する。
      // したがって .ts の未定義参照の担保は typecheck:viewer にある。
      "@typescript-eslint/no-unused-vars": ["error", unusedVarsOptions],
    },
  },
];
