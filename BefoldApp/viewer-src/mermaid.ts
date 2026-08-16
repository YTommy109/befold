// mermaid の遅延ロード・設定・実行。

import { prefersDark } from './color-scheme.js';
import { _mmdDocument } from './document-state.js';
import { _mmdWrapDiagrams } from './zoom.js';

// mermaid はバンドルに含めず <script> で遅延ロードするグローバル
// (_mmdEnsureMermaidLoaded を参照)。npm の型を import すると esbuild が
// 実体をバンドルへ引き込みかねないため、このモジュールで使う範囲だけを
// ローカルに宣言する。
interface MermaidGlobal {
  initialize(config: MermaidConfig): void;
  run(options: { nodes: HTMLElement[] }): Promise<void>;
  parseError?: (err: MermaidParseErrorLike) => void;
}

// mermaid が parseError へ渡すエラー。message / str のどちらで来るかは
// 発生箇所で異なるため、どちらも省略可能にしてある。
interface MermaidParseErrorLike {
  message?: string;
  str?: string;
}

declare const mermaid: MermaidGlobal;

// OS のカラースキームに対応する mermaid テーマ名を返す。
// prefers-color-scheme: dark のとき 'dark'、それ以外は 'default'。
function mermaidTheme(isDark: boolean): 'dark' | 'default' {
  return isDark ? 'dark' : 'default';
}

// mermaid.initialize へ渡す設定。ここで組み立てるキーだけを持つ。
interface MermaidConfig {
  startOnLoad: boolean;
  theme: 'dark' | 'default';
  securityLevel: string;
  maxTextSize: number;
  maxEdges: number;
  sequence: { useMaxWidth: boolean };
  er: { useMaxWidth: boolean };
  flowchart: { useMaxWidth: boolean };
  gantt: { useMaxWidth: boolean };
  journey: { useMaxWidth: boolean };
  pie: { useMaxWidth: boolean };
  state: { useMaxWidth: boolean };
  class: { useMaxWidth: boolean };
}

// theme 以外の設定は固定。カラースキームに応じて theme だけ差し替える。
function _mmdMermaidConfig(): MermaidConfig {
  return {
    startOnLoad: false,
    theme: mermaidTheme(prefersDark()),
    // 図ラベル内の生 HTML をサニタイズする（デフォルトだが将来の既定変更に備えて明示）
    securityLevel: 'strict',
    // mermaid.js のデフォルト上限（50,000文字/500エッジ）はアプリが許容するテキストファイル上限（10MB）より
    // はるかに小さく、大きめの図が "Maximum text size in diagram exceeded" になるため引き上げる。
    maxTextSize: 10 * 1024 * 1024,
    maxEdges: 10000,
    sequence: { useMaxWidth: false },
    er: { useMaxWidth: false },
    flowchart: { useMaxWidth: false },
    gantt: { useMaxWidth: false },
    journey: { useMaxWidth: false },
    pie: { useMaxWidth: false },
    state: { useMaxWidth: false },
    class: { useMaxWidth: false },
  };
}

function _mmdMermaidParseError(err: MermaidParseErrorLike | null | undefined): void {
  var msg = (err && (err.message || err.str)) || String(err);
  // #mmd-error / #diagram-wrap は viewer.html に静的に存在する（truncation.ts の
  // 非 null 表明と同じ理由。表明は実行時の振る舞いを変えない）。
  var panel = document.getElementById('mmd-error')!;
  panel.textContent = msg;
  panel.style.display = 'block';
  if (_mmdDocument.type() === 'mmd') {
    document.getElementById('diagram-wrap')!.style.display = 'none';
  }
}

// mermaid.min.js（3.2MB）は CSV・ログ・コード・SVG・HTML ソース等の mermaid 不使用
// プレビューでは無駄なパース/評価コストになるため、mermaid を実際に描画する瞬間まで
// ロードを遅延する。<script> をDOM挿入する方式は WKWebView の CSP（script-src 'self'）
// にも適合する。Promise をキャッシュし、複数回呼ばれても2回ロードしない。
var _mermaidLoadPromise: Promise<void> | null = null;
function _mmdEnsureMermaidLoaded(): Promise<void> {
  if (_mermaidLoadPromise) return _mermaidLoadPromise;
  _mermaidLoadPromise = new Promise<Event>(function (resolve, reject) {
    var script = document.createElement('script');
    script.src = 'mermaid.min.js';
    script.addEventListener('load', resolve);
    script.addEventListener('error', function () {
      reject(new Error('mermaid.min.js failed to load'));
    });
    document.head.append(script);
    // 連鎖の終端で、戻り値は誰も見ない（呼び出し側は完了だけを待つ）。
    // oxlint-disable-next-line promise/always-return
  }).then(function () {
    mermaid.initialize(_mmdMermaidConfig());
    mermaid.parseError = _mmdMermaidParseError;
  });
  return _mermaidLoadPromise;
}

// カラースキームが切り替わったときに呼ぶ。未ロードなら何もしない: 次回の
// _mmdEnsureMermaidLoaded() が現在のカラースキームで初期化するため。
function _mmdReinitializeMermaidIfLoaded(): void {
  if (_mermaidLoadPromise) {
    mermaid.initialize(_mmdMermaidConfig());
  }
}

// 描画後の DOM に .mermaid があれば mermaid を実行し、ズーム用ラッパーで包む。
// mmd 直接表示だけでなく Markdown 内の ```mermaid フェンスもここを通る。
// onlyUnprocessed が true の場合、まだ描画していない図だけを対象にする
// (チャンク追記時に既存の図まで作り直さないため)。
async function _mmdRunMermaid(diagramWrap: HTMLElement, onlyUnprocessed?: boolean): Promise<void> {
  var selector = onlyUnprocessed ? '.mermaid:not([data-processed])' : '.mermaid';
  var elements = diagramWrap.querySelectorAll<HTMLElement>(selector);
  if (elements.length === 0) {
    return;
  }
  try {
    await _mmdEnsureMermaidLoaded();
    elements.forEach(function (el: HTMLElement, i: number) {
      if (!onlyUnprocessed) {
        delete el.dataset.processed;
      }
      el.id = 'mmd-' + i + '-' + Date.now();
    });
    await mermaid.run({ nodes: Array.from(elements) });
  } catch (e) {
    // parseError callback handles parse-time display; load failure falls through silently
  }
  _mmdWrapDiagrams(diagramWrap);
}

export {
  mermaidTheme,
  _mmdMermaidConfig,
  _mmdMermaidParseError,
  _mmdReinitializeMermaidIfLoaded,
  _mmdRunMermaid,
};
