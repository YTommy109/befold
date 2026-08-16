// ソースコードのハイライトと行単位 HTML の組み立て。
// 初回描画(renderCodeHtml)・チャンク追記(codeChunkInnerHtml)・差分表示(diff-html.js)が
// この 1 本を共有する。

import { escapeHtml } from './encoding.js';

/// 依存注入される highlight.js の最小インターフェース。viewer.html では
/// グローバルの hljs、テストでは npm の highlight.js が渡る。実体の型を
/// 直接使わないのは、注入元が 2 通りある(片方はグローバル)ため。
/// 注入されないホストがあるので、呼び出し側は null/undefined を渡しうる。
interface CodeHighlighter {
  getLanguage(name: string): unknown;
  highlight(code: string, options: { language: string; ignoreIllegals: boolean }): { value: string };
}

/// leadingIndentInfo() が返すインデントガイド描画用の情報。
interface IndentInfo {
  cols: number;
  depth: number;
}

// class 属性に埋め込める文字(英数字・_・+・-)だけを残す。
// hljs.getLanguage() を通過した言語名しか来ないはずだが、防御的に二重チェックする。
function sanitizeLang(lang: unknown): string {
  return String(lang).replace(/[^\w+-]/g, '');
}

// コードのシンタックスハイライト。markdown-it の highlight オプションからも呼ばれる。
// hljs は依存注入(viewer.html ではグローバル hljs、テストでは npm の highlight.js)。
// 返り値が '<pre' で始まる場合 markdown-it はそれをそのまま採用し、
// '' の場合はデフォルトのエスケープ済み <pre><code> にフォールバックする。
function highlightCode(
  hljs: CodeHighlighter | null | undefined,
  str: string,
  lang: string | undefined,
): string {
  if (hljs && lang && hljs.getLanguage(lang)) {
    try {
      var result = hljs.highlight(str, { language: lang, ignoreIllegals: true });
      return (
        '<pre><code class="hljs language-' +
        sanitizeLang(lang) +
        '">' +
        result.value +
        '</code></pre>'
      );
    } catch (e) {
      // フォールバックへ
    }
  }
  return '';
}

// HTML を行ごとに分割し、各行を自己完結な HTML にする(未クローズ span が
// 後続行を壊すのを防ぐ)。highlight.js はブロックコメント等で改行をまたぐ
// <span> を出力するため、行末で開いたままの span を閉じ、次の行の先頭で
// 開き直す。buildLineNumberRows(行番号付与) と codeChunkInnerHtml
// (チャンク境界の前方文脈を落とす処理)の双方から使う。
function reflowSpanBalancedLines(codeHtml: string): string[] {
  var lines = codeHtml.split('\n');
  // 末尾が空行の場合は除去する(highlight.js が末尾に \n を付けることがある)
  if (lines.length > 1 && lines[lines.length - 1] === '') {
    lines.pop();
  }
  var openSpans: string[] = [];
  var result: string[] = [];
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i] || '';
    var reopen = openSpans.join('');
    var tagRe = /<span\b[^>]*>|<\/span>/g;
    var tag: RegExpExecArray | null;
    while ((tag = tagRe.exec(line)) !== null) {
      if (tag[0] === '</span>') {
        openSpans.pop();
      } else {
        openSpans.push(tag[0]);
      }
    }
    var close = '';
    for (var j = 0; j < openSpans.length; j++) {
      close += '</span>';
    }
    result.push(reopen + line + close);
  }
  return result;
}

// インデントガイド(縦線)の桁幅。ガイドはこの桁数ごとに 1 本引く。
// style.css の tab-size と必ず一致させること。
var CODE_TAB_SIZE = 4;

// プレーンな文字列の先頭空白をタブ幅換算の桁数に変換する。タブは次の
// tab-stop まで、スペースは +1。非空白に達したら打ち切る。
function indentColumns(text: string, tabSize: number): number {
  var cols = 0;
  for (var i = 0; i < text.length; i++) {
    var ch = text[i];
    if (ch === '\t') {
      cols += tabSize - (cols % tabSize);
    } else if (ch === ' ') {
      cols += 1;
    } else {
      break;
    }
  }
  return cols;
}

// ハイライト済みの 1 行 HTML から、インデントガイド描画用の情報を求める。
// reflow が前置する開き <span> タグを飛ばしてから先頭空白を桁数換算する。
// cols=先頭インデント桁数、depth=引くガイド本数(floor(cols/tabSize))。
// 非空白を含まない行(空行・空白のみ)はガイドを引かない(depth 0)。
function leadingIndentInfo(lineHtml: string, tabSize: number): IndentInfo {
  var rest = lineHtml;
  var openTag = /^<span\b[^>]*>/;
  var match: RegExpExecArray | null;
  while ((match = openTag.exec(rest)) !== null) {
    rest = rest.slice(match[0].length);
  }
  var cols = 0;
  var hasContent = false;
  for (var i = 0; i < rest.length; i++) {
    var ch = rest[i];
    if (ch === '\t') {
      cols += tabSize - (cols % tabSize);
    } else if (ch === ' ') {
      cols += 1;
    } else {
      hasContent = true;
      break;
    }
  }
  if (!hasContent) {
    return { cols: 0, depth: 0 };
  }
  return { cols: cols, depth: Math.floor(cols / tabSize) };
}

// 1 行分の <td class="line-content"> を組み立てる。インデントがある行には
// ハンギングインデントとガイド描画用の CSS 変数を付与する(depth 0 の行は付けない)。
function lineContentCell(lineHtml: string): string {
  var info = leadingIndentInfo(lineHtml, CODE_TAB_SIZE);
  var style =
    info.depth > 0
      ? ' style="--indent-cols:' + info.cols + ';--indent-depth:' + info.depth + '"'
      : '';
  return '<td class="line-content"' + style + '>' + lineHtml + '</td>';
}

// 行ごとに分割した HTML を <tr> 列(文字列連結)に組み立てる。
// 行番号セルは showLineNumbers === true のときだけ付ける(省略時は付けない)。
// この「明示的に true のときだけ」という規則を行番号系の関数すべてで共有する
// (省略時の解釈が関数ごとに違うと、呼び出し漏れが表示差になって現れるため)。
// 行番号は startLine から振る(チャンク追記では既存行数 + 1 を渡す)。
function buildLineNumberRows(
  codeHtml: string,
  startLine: number,
  showLineNumbers: boolean | undefined,
): string {
  var withNumbers = showLineNumbers === true;
  var lines = reflowSpanBalancedLines(codeHtml);
  var rows = '';
  for (var i = 0; i < lines.length; i++) {
    var numberCell = withNumbers ? '<td class="line-number">' + (startLine + i) + '</td>' : '';
    rows += '<tr>' + numberCell + lineContentCell(lines[i]!) + '</tr>';
  }
  return rows;
}

// コード全文を行単位の <table> で包む(初回描画用)。
// 行番号有無に関わらず常にこの行単位構造を使い、インデントガイドを描けるようにする。
function wrapWithLineNumbers(codeHtml: string, showLineNumbers: boolean | undefined): string {
  return (
    '<table class="code-table">' + buildLineNumberRows(codeHtml, 1, showLineNumbers) + '</table>'
  );
}

// 単一コードファイル全文のハイライト HTML を組み立てる。
// highlightCode() を再利用し、未対応言語・hljs 不在・例外時は
// エスケープ済みプレーンへフォールバックする。行番号有無に関わらず、内容は常に
// 行単位 <table> で包む(インデントガイドを両パスで描くため)。
function renderCodeHtml(
  hljs: CodeHighlighter | null | undefined,
  str: string,
  lang: string | undefined,
  showLineNumbers: boolean | undefined,
): string {
  // 省略時は行番号なし(従来の既定)。行番号セルの有無だけが変わり、行単位構造は共通。
  var withNumbers = showLineNumbers === true;
  var highlighted = highlightCode(hljs, str, lang);
  if (highlighted) {
    // <pre><code ...>CONTENT</code></pre> の CONTENT だけを行単位テーブルで包む
    var match = highlighted.match(/^(<pre><code[^>]*>)([\s\S]*)(<\/code><\/pre>)$/);
    if (match) {
      return match[1]! + wrapWithLineNumbers(match[2]!, withNumbers) + match[3]!;
    }
  }
  return '<pre><code>' + wrapWithLineNumbers(escapeHtml(str), withNumbers) + '</code></pre>';
}

// チャンク追記用のコード HTML。highlightCode の <pre><code…> ラッパーを剥がした
// 中身だけを返し、ハイライト不可(hljs 不在・未対応言語)の場合はエスケープ済み
// プレーンテキストにフォールバックする。DOM への挿入は render.js の appendChunk が行う。
// contextStr(改行終端済みの直前チャンクの末尾行、任意)を渡すと、
// contextStr + str をまとめて highlight.js にかけてから contextStr 分の
// 行を取り除いて返す。highlight.js はチャンクをまたいだ継続状態を持たない
// (v11 で continuation 引数は廃止済み)ため、ブロックコメントや複数行文字列が
// チャンク境界をまたぐと、文脈なしでは境界直後が通常コードとして誤ハイライト
// される。境界前の数百行を文脈として与えることで、hljs が正しい字句状態
// (コメント内/文字列内など)を自力で再構築できるようにする。
function codeChunkInnerHtml(
  hljs: CodeHighlighter | null | undefined,
  str: string,
  lang: string | undefined,
  contextStr: string | undefined,
): string {
  if (contextStr) {
    var highlightedWithContext = highlightCode(hljs, contextStr + str, lang);
    if (highlightedWithContext) {
      var inner = highlightedWithContext
        .replace(/^<pre><code[^>]*>/, '')
        .replace(/<\/code><\/pre>$/, '');
      var lines = reflowSpanBalancedLines(inner);
      var contextLineCount = (contextStr.match(/\n/g) || []).length;
      var body = lines.slice(contextLineCount).join('\n');
      return str.endsWith('\n') ? body + '\n' : body;
    }
  }
  var highlighted = highlightCode(hljs, str, lang);
  if (highlighted) {
    return highlighted.replace(/^<pre><code[^>]*>/, '').replace(/<\/code><\/pre>$/, '');
  }
  return escapeHtml(str);
}

// str の末尾から改行終端済みの行を最大 maxLines 行分切り出す(文脈として
// highlight.js に渡す用)。全文をスキャンせず末尾から lastIndexOf を
// maxLines 回たどるだけなので、str が巨大でもコストは maxLines に比例する。
function lastLines(str: string, maxLines: number): string {
  if (str.length === 0) {
    return '';
  }
  var idx = str.length - 1;
  var count = 0;
  while (count < maxLines) {
    var nl = str.lastIndexOf('\n', idx - 1);
    if (nl === -1) {
      return str;
    }
    idx = nl;
    count++;
  }
  return str.slice(idx + 1);
}

export {
  CODE_TAB_SIZE,
  sanitizeLang,
  highlightCode,
  reflowSpanBalancedLines,
  indentColumns,
  leadingIndentInfo,
  lineContentCell,
  buildLineNumberRows,
  wrapWithLineNumbers,
  renderCodeHtml,
  codeChunkInnerHtml,
  lastLines,
};
