// 表示種別ごとの #diagram-wrap 組み立て。
// いずれも #diagram-wrap を受け取り、その中身と自分のクラスだけを組み立てる。
// クラスの一括除去・blob URL の解放・mermaid 実行・パス注釈・検索/ズーム/
// スクロール復元といった型共通の後処理は render() 側が担う。

import { renderCodeHtml } from './code-html.js';
import { buildTableHtml, parseCsv, renderCsvSourceHtml } from './csv-html.js';
import { renderDiffHtml } from './diff-html.js';
import { base64ToBytes, escapeHtml, imageDataURI, svgDataURI } from './encoding.js';
import { markdownRenderer } from './markdown.js';
import { hljs } from './vendor.js';
import { _mmdViewOptions } from './view-options.js';
import { _mmdApplyDiagramZoom, _mmdBuildDiagramControls, _mmdFitImage } from './zoom.js';

// #diagram-wrap に付く「表示種別」クラスの全集合。表示種別を追加したらここに足す。
// 付け替えは必ず _mmdSetBodyClasses 経由にする(外す側の一覧が複数箇所に手写しされて
// いると、追加時の更新漏れで前の型のスタイルが残る)。
type ViewerBodyClass =
  | 'markdown-body'
  | 'code-body'
  | 'html-body'
  | 'csv-body'
  | 'image-body'
  | 'pdf-body';

// render() が選ぶ描画形(表示種別 → 描画関数のディスパッチで使う集合)。
// render.js の renderShape() が返す値の全体で、'diff' だけは例外的に
// 「差分テーブルを描いた」という実際の結果としてのみ現れる(_renderSource の戻り値)。
type RenderShape =
  | 'code'
  | 'csv-source'
  | 'mmd'
  | 'svg'
  | 'html'
  | 'csv-table'
  | 'image'
  | 'pdf'
  | 'markdown';

// 行番号付きソース表示を通る描画形。
type SourceShape = 'code' | 'csv-source';

var BODY_CLASSES: ViewerBodyClass[] = [
  'markdown-body',
  'code-body',
  'html-body',
  'csv-body',
  'image-body',
  'pdf-body',
];

// 表示種別クラスを一括で付け替える。keep に挙げたものだけが残る。
function _mmdSetBodyClasses(el: HTMLElement, ...keep: ViewerBodyClass[]): void {
  BODY_CLASSES.forEach(function (name) {
    el.classList.toggle(name, keep.indexOf(name) >= 0);
  });
}

// PDF 表示用に生成した blob URL。生成と解放をこの owner に閉じ、再描画のたびに
// release() してリークを防ぐ(PDF 以外への切替も含む)。
function _createPdfBlobHolder() {
  var url: string | null = null;
  return {
    issue: function (bytes: Uint8Array): string {
      // base64ToBytes() は常に自前で確保した ArrayBuffer 上の Uint8Array を返すが、
      // 戻り値の型 Uint8Array(= ArrayBufferLike)は SharedArrayBuffer 上のものも
      // 含むため BlobPart に直接は代入できない。実行時に SharedArrayBuffer が
      // 渡ることはないので BlobPart として扱う。
      url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: 'application/pdf' }));
      return url;
    },
    release: function (): void {
      if (!url) {
        return;
      }
      URL.revokeObjectURL(url);
      url = null;
    },
  };
}

var _mmdPdfBlob = _createPdfBlobHolder();

function _renderMmd(diagramWrap: HTMLElement, content: string): void {
  diagramWrap.innerHTML = '<pre class="mermaid">' + escapeHtml(content) + '</pre>';
}

function _renderSvg(diagramWrap: HTMLElement, content: string): void {
  var img = document.createElement('img');
  img.src = svgDataURI(content);
  img.style.maxWidth = '100%';
  img.alt = 'SVG';
  // mermaid ダイアグラムと同じズーム用ラッパーで包む
  var wrap = document.createElement('div');
  wrap.className = 'diagram-zoom-wrap';
  wrap.dataset.diagramIndex = '0';
  var scroll = document.createElement('div');
  scroll.className = 'diagram-zoom-scroll';
  var inner = document.createElement('div');
  inner.className = 'diagram-zoom-inner';
  inner.appendChild(img);
  scroll.appendChild(inner);
  wrap.appendChild(scroll);
  wrap.appendChild(_mmdBuildDiagramControls(wrap));
  diagramWrap.innerHTML = '';
  diagramWrap.appendChild(wrap);
  img.onload = function (): void {
    // dataset は文字列しか受け取らないため明示的に文字列化する
    // (代入時の暗黙変換と同じ結果で、実行時の値は変わらない)。
    wrap.dataset.naturalHeight = String(inner.offsetHeight);
    _mmdApplyDiagramZoom(wrap);
  };
}

function _renderHtml(diagramWrap: HTMLElement, content: string): void {
  diagramWrap.classList.add('html-body');
  var iframe = document.createElement('iframe');
  // 属性で直接指定する(iframe.sandbox はブラウザにより DOMTokenList 反映の
  // 実装差があり、属性値としての確認もしづらいため)。
  iframe.setAttribute('sandbox', 'allow-same-origin');
  iframe.srcdoc = content;
  iframe.style.width = '100%';
  iframe.style.border = 'none';
  // iframe の高さをコンテンツに合わせる
  iframe.onload = function (): void {
    try {
      // contentDocument が null のときは同じ行で TypeError になり catch へ落ちる。
      // 非 null 表明はその振る舞いを変えない(従来から null 参照を catch で拾っている)。
      var h = iframe.contentDocument!.documentElement.scrollHeight;
      iframe.style.height = h + 'px';
    } catch (e) {
      iframe.style.height = '80vh';
    }
  };
  iframe.style.height = '80vh';
  diagramWrap.innerHTML = '';
  diagramWrap.appendChild(iframe);
}

function _renderCsv(diagramWrap: HTMLElement, content: string, lang: string | undefined): void {
  // github-markdown-css のテーブル装飾(markdown-body)を土台にしつつ、
  // CSV 専用の上書き(style.css の csv-body)をそこにだけ効かせる。
  // 通常の Markdown テーブルは markdown-body のみを付与するため影響しない。
  diagramWrap.classList.add('markdown-body', 'csv-body');
  diagramWrap.innerHTML = buildTableHtml(parseCsv(content, lang || ','));
}

function _renderImage(diagramWrap: HTMLElement, content: string, lang: string | undefined): void {
  // 初期表示はウィンドウに収まるサイズ(縦横とも)にフィットさせる。
  // フィット後は #diagram-wrap への全体ズーム(⌘+/-/0、Ctrl+ホイール)が
  // フィット状態を基準に乗算する(imageFitSize のコメント参照)。
  diagramWrap.classList.add('image-body');
  var img = document.createElement('img');
  img.alt = 'Image';
  img.onload = function (): void {
    _mmdFitImage(img, diagramWrap);
  };
  img.src = imageDataURI(content, lang);
  diagramWrap.innerHTML = '';
  diagramWrap.appendChild(img);
}

function _renderPdf(diagramWrap: HTMLElement, content: string): void {
  // data: URI ではなく blob: URL を使う。CSP の frame-src は blob: のみを
  // 許可しており、blob URL はこのスクリプトが生成した推測不能なものに
  // 限られるため、Markdown 内に静的に書かれた iframe はロードできない。
  diagramWrap.classList.add('pdf-body');
  var iframe = document.createElement('iframe');
  iframe.src = _mmdPdfBlob.issue(base64ToBytes(content));
  diagramWrap.innerHTML = '';
  diagramWrap.appendChild(iframe);
}

// markdown-it はバンドル同梱(vendor.js)で常に構成済みのため、
// 「未ロードにつき後続処理を打ち切る」経路は無い。
function _renderMarkdown(diagramWrap: HTMLElement, content: string): void {
  // github-markdown-css は .markdown-body プレフィックス前提のため
  // Markdown レンダリング時のみ付与する
  diagramWrap.classList.add('markdown-body');
  diagramWrap.innerHTML = markdownRenderer().render(content);
}

// 行番号付きソース表示のビルダー。ソース表示のテキスト種別も、常にソースである
// コード種別('.swift' 等)も、CSV/TSV のソース表示もここ 1 本を通る。
// 入口を分けていた頃は「.md では差分が出るのに .swift では出ない」形の抜けが起きた。
//
// 戻り値は「実際に描いた形」。差分テーブルを描いた場合だけ 'diff' になり、
// それ以外は渡された shape をそのまま返す。呼び出し元(render)がこの値を
// appendChunk 用の記録へ反映する(記録の書き手を render の 1 箇所に閉じるため)。
function _renderSource(
  diagramWrap: HTMLElement,
  content: string,
  type: string,
  lang: string | undefined,
  shape: SourceShape,
): SourceShape | 'diff' {
  _mmdSetBodyClasses(diagramWrap, 'code-body');
  // 差分が届いていれば差分表示を優先する。パースできず空文字列が返った場合は
  // 通常のソース表示へ落ちる(差分が壊れていても内容は必ず読める)。
  var diffHtml = _renderDiffHtmlIfAvailable(type, lang);
  if (diffHtml !== '') {
    diagramWrap.innerHTML = diffHtml;
    return 'diff';
  }
  diagramWrap.innerHTML =
    shape === 'csv-source'
      ? renderCsvSourceHtml(content, lang || ',', _mmdViewOptions.lineNumbers())
      : renderCodeHtml(hljs, content, _sourceLanguage(type, lang), _mmdViewOptions.lineNumbers());
  return shape;
}

// ソース表示の言語決定。差分表示と通常表示で同じ規則を使う。
function _sourceLanguage(type: string, lang: string | undefined): string {
  if (type === 'svg' || type === 'html') {
    return 'xml';
  }
  if (type === 'md') {
    return 'markdown';
  }
  return lang || 'plaintext';
}

// 差分が届いていればインライン差分の HTML を返す。無ければ空文字列。
// CSV/TSV のソース表示は独自の列構造を持つため、差分表示の対象にしない。
function _renderDiffHtmlIfAvailable(type: string, lang: string | undefined): string {
  var diff = _mmdViewOptions.diff();
  if (diff === null || type === 'csv') {
    return '';
  }
  try {
    return renderDiffHtml(
      hljs,
      diff,
      _sourceLanguage(type, lang),
      _mmdViewOptions.lineNumbers(),
      _mmdViewOptions.diffLayout(),
    );
  } catch (e) {
    return '';
  }
}

export type { RenderShape, SourceShape, ViewerBodyClass };

export {
  BODY_CLASSES,
  _mmdSetBodyClasses,
  _mmdPdfBlob,
  _renderMmd,
  _renderSvg,
  _renderHtml,
  _renderCsv,
  _renderImage,
  _renderPdf,
  _renderMarkdown,
  _renderSource,
  _sourceLanguage,
};
