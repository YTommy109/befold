import { exposeGlobals } from './expose.js';
// viewer バンドルのエントリ（TASK-432.2 / TASK-432.3）。
//
// viewer.html は body 末尾でこの成果物（viewer-bundle.js）を 1 本だけ読み込む。
// ベンダー（markdown-it / highlight.js / DOMPurify）はバンドルに含めず、
// viewer.html が先に classic script として読み込んだグローバルを参照する。
// mermaid は 3.2MB あり、mermaid を使わないプレビューでは無駄なパースコストに
// なるため、描画の瞬間まで遅延ロードする形を維持している。
import * as main from './main.js';

exposeGlobals(main);

// classic script 時代は viewer-main.js の末尾（module 不在の分岐）で即時初期化していた。
// バンドルでは body 末尾の <script src="viewer-bundle.js"> がその位置にあたる。
main._mmdInit();
