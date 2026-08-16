// git 差分表示。unified diff の解析と、インライン/左右分割 2 レイアウトの HTML 組み立て。
// 既存のソース表示と同じ <table class="code-table"> 構造に載せるため、行番号・
// インデントガイド・シンタックスハイライト・検索がそのまま効く。

import { highlightCode, lineContentCell, reflowSpanBalancedLines } from './code-html.js';
import { escapeHtml } from './encoding.js';

/// 依存注入される highlight.js の最小インターフェース。code-html.ts が
/// highlightCode に定めているものと同一で、そこから引き写す
/// (同じ形の interface をこちらで二重に定義すると片方だけずれる)。
type CodeHighlighter = Parameters<typeof highlightCode>[0];

/// 差分行の種別。旧側・新側のどちらに現れるかを決める。
type DiffLineType = 'context' | 'add' | 'del';

/// unified diff の 1 行。oldNumber / newNumber は片側にしか無い行では null。
interface DiffLine {
  type: DiffLineType;
  text: string;
  oldNumber: number | null;
  newNumber: number | null;
}

/// unified diff の 1 ハンク。oldStart / newStart は `@@ -a,b +c,d @@` の開始行番号。
interface DiffHunk {
  oldStart: number;
  newStart: number;
  lines: DiffLine[];
}

/// unified diff の 1 ファイル分。パスはヘッダが無ければ null のまま。
interface DiffFile {
  oldPath: string | null;
  newPath: string | null;
  isBinary: boolean;
  hunks: DiffHunk[];
}

/// 左右分割で 1 行に並べる旧側 / 新側の対。値は `hunk.lines` の添字で、
/// 対応する行が無い側は null。
interface DiffLinePair {
  left: number | null;
  right: number | null;
}

// unified diff の 1 ハンクのヘッダー。`@@ -12,7 +12,9 @@ ...` の数値部だけを見る。
var DIFF_HUNK_HEADER = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;

// unified diff をファイル → ハンク → 行の構造へ分解する。
// 行の種別は 'context' / 'add' / 'del' の 3 つで、旧側・新側の行番号を各行に付ける
// (描画側で 2 本のガターに出すため。片側にしか無い行はもう一方が null)。
// `\ No newline at end of file` は直前の行に対する注記であり、行としては数えない。
function parseUnifiedDiff(text: unknown): DiffFile[] {
  var files: DiffFile[] = [];
  var file: DiffFile | null = null;
  var hunk: DiffHunk | null = null;
  var oldNumber = 0;
  var newNumber = 0;
  var lines = String(text ?? '').split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]!;
    if (line.indexOf('diff --git ') === 0) {
      file = { oldPath: null, newPath: null, isBinary: false, hunks: [] };
      files.push(file);
      hunk = null;
      continue;
    }
    if (file === null) {
      continue;
    }
    // ヘッダ類はハンクが始まる前にしか現れない。ハンク内で同じ接頭辞を持つ行は
    // 本文（`-- ` で始まる SQL コメントの削除など）なので、ここで消費しない。
    if (hunk === null) {
      if (line.indexOf('--- ') === 0) {
        file.oldPath = diffPath(line.slice(4));
        continue;
      }
      if (line.indexOf('+++ ') === 0) {
        file.newPath = diffPath(line.slice(4));
        continue;
      }
      if (line.indexOf('Binary files ') === 0 || line.indexOf('GIT binary patch') === 0) {
        file.isBinary = true;
        continue;
      }
    }
    var header = line.match(DIFF_HUNK_HEADER);
    if (header) {
      oldNumber = parseInt(header[1]!, 10);
      newNumber = parseInt(header[3]!, 10);
      hunk = { oldStart: oldNumber, newStart: newNumber, lines: [] };
      file.hunks.push(hunk);
      continue;
    }
    if (hunk === null) {
      continue;
    }
    if (line.indexOf('\\') === 0) {
      continue;
    }
    var marker = line.charAt(0);
    var body = line.slice(1);
    if (marker === '+') {
      hunk.lines.push({ type: 'add', text: body, oldNumber: null, newNumber: newNumber });
      newNumber += 1;
    } else if (marker === '-') {
      hunk.lines.push({ type: 'del', text: body, oldNumber: oldNumber, newNumber: null });
      oldNumber += 1;
    } else if (marker === ' ') {
      // 空文字列の行は本文ではない(git は空の文脈行も先頭 1 文字の空白を付けて出す)。
      // 末尾の改行で生じる空要素を文脈行として数えると、以降の行番号が 1 つずれる。
      hunk.lines.push({ type: 'context', text: body, oldNumber: oldNumber, newNumber: newNumber });
      oldNumber += 1;
      newNumber += 1;
    }
  }
  return files;
}

// `a/path/to/file.swift` の接頭辞を落とす。`/dev/null` はそのまま返す(新規・削除の印)。
function diffPath(raw: string): string {
  var path = raw.split('\t')[0]!;
  if (path === '/dev/null') {
    return path;
  }
  return path.replace(/^[ab]\//, '');
}

// 添字の並び(旧側 or 新側)の本文をまとめてハイライトし、行ごとの HTML 配列で返す。
// 1 行ずつ hljs へ渡すとブロックコメントや複数行文字列で字句状態が切れるため、
// 片側分をまとめて 1 ブロックとして扱う(行をまたぐトークンは側の中で閉じる)。
// reflowSpanBalancedLines は highlight.js が付ける末尾の \n を落とす作りなので、
// 最終行が空行(末尾が空行のファイル)だと本物の行まで消える。足りない分は空で埋める。
function highlightedSideLines(
  hljs: CodeHighlighter,
  lines: DiffLine[],
  indexes: number[],
  lang: string | undefined,
): string[] {
  var texts: string[] = [];
  for (var i = 0; i < indexes.length; i++) {
    texts.push(lines[indexes[i]!]!.text);
  }
  var joined = texts.join('\n');
  var lineHtmls: string[] | null = null;
  var highlighted = highlightCode(hljs, joined, lang);
  if (highlighted) {
    var match = highlighted.match(/^<pre><code[^>]*>([\s\S]*)<\/code><\/pre>$/);
    if (match) {
      lineHtmls = reflowSpanBalancedLines(match[1]!);
    }
  }
  if (lineHtmls === null) {
    lineHtmls = reflowSpanBalancedLines(escapeHtml(joined));
  }
  while (lineHtmls.length < indexes.length) {
    lineHtmls.push('');
  }
  return lineHtmls.slice(0, indexes.length);
}

// ハンク 1 つ分をハイライトし、行ごとの HTML 配列で返す。
// 旧版(文脈行 + 削除行)と新版(文脈行 + 追加行)を別々にハイライトする。
// 両者を 1 ブロックに連結すると、変更行の旧版と新版が隣接して字句状態が壊れ
// (文字列リテラルやコメントの開始・終了が二重になる)、以降の行の色が総崩れになる。
// GitDiffReader は -U1000000 でファイル全体を 1 ハンクにするため、崩れは末尾まで及ぶ。
// 戻り値は必ず hunk.lines と同じ長さにする。呼び出し側は行 HTML を添字で引く
// (左右分割は対の添字で引く)ため、長さがずれると undefined を掴んで落ちる。
// 文脈行は両側に現れるが、色は同じになるので新版側の結果を採用する。
function highlightedDiffLines(
  hljs: CodeHighlighter,
  hunk: DiffHunk,
  lang: string | undefined,
): string[] {
  var lines = hunk.lines;
  var oldIndexes: number[] = [];
  var newIndexes: number[] = [];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i]!.type !== 'add') {
      oldIndexes.push(i);
    }
    if (lines[i]!.type !== 'del') {
      newIndexes.push(i);
    }
  }
  var result: string[] = [];
  for (var n = 0; n < lines.length; n++) {
    result.push('');
  }
  var oldHtmls = highlightedSideLines(hljs, lines, oldIndexes, lang);
  for (var o = 0; o < oldIndexes.length; o++) {
    result[oldIndexes[o]!] = oldHtmls[o]!;
  }
  var newHtmls = highlightedSideLines(hljs, lines, newIndexes, lang);
  for (var w = 0; w < newIndexes.length; w++) {
    result[newIndexes[w]!] = newHtmls[w]!;
  }
  return result;
}

// 行種別を表す記号。背景色だけだと色覚特性やハイコントラスト設定で追加・削除を
// 区別できないため、色に依存しないグリフを必ず添える。インライン表示と左右分割で
// 同じ記号を使う(片方だけ変えると同じハンクが 2 つのレイアウトで食い違う)。
function diffMarkerGlyph(type: DiffLineType): string {
  if (type === 'add') {
    return '+';
  }
  if (type === 'del') {
    return '-';
  }
  return ' ';
}

// 1 行分の <tr>。種別クラスと記号セルを必ず持たせる。
function diffRow(line: DiffLine, lineHtml: string, showLineNumbers: boolean | undefined): string {
  var numbers = '';
  if (showLineNumbers === true) {
    numbers =
      '<td class="line-number diff-old">' +
      (line.oldNumber === null ? '' : line.oldNumber) +
      '</td><td class="line-number diff-new">' +
      (line.newNumber === null ? '' : line.newNumber) +
      '</td>';
  }
  return (
    '<tr class="diff-line diff-' +
    line.type +
    '">' +
    numbers +
    '<td class="diff-marker" aria-hidden="true">' +
    diffMarkerGlyph(line.type) +
    '</td>' +
    lineContentCell(lineHtml) +
    '</tr>'
  );
}

// ハンクの区切り行。`@@ -1,3 +1,4 @@` の位置情報は出さず、連続していない範囲の
// 境目だけを示す。どこの行かは両側のガターが持っているため、位置情報は重複した情報になる。
// 桁数はレイアウトと行番号ガターの有無で変わるため、colspan は呼び出し側が決める。
function diffHunkSeparatorRow(colspan: number): string {
  return (
    '<tr class="diff-hunk" aria-hidden="true">' +
    '<td class="diff-hunk-separator" colspan="' +
    colspan +
    '"></td></tr>'
  );
}

// unified diff を 1 列(インライン)の差分表示 HTML へ組み立てる。
// 差分が 1 つも無ければ空文字列を返し、呼び出し側は通常のソース表示へ戻す。
function renderInlineDiffHtml(
  hljs: CodeHighlighter,
  diffText: unknown,
  lang: string | undefined,
  showLineNumbers: boolean | undefined,
): string {
  var files = parseUnifiedDiff(diffText);
  var rows = '';
  for (var f = 0; f < files.length; f++) {
    var hunks = files[f]!.hunks;
    for (var h = 0; h < hunks.length; h++) {
      var hunk = hunks[h]!;
      var lineHtmls = highlightedDiffLines(hljs, hunk, lang);
      // 先頭には区切りを置かない(境目が無いところに帯だけが出るため)。
      if (rows !== '') {
        rows += diffHunkSeparatorRow(showLineNumbers === true ? 4 : 2);
      }
      for (var i = 0; i < hunk.lines.length; i++) {
        rows += diffRow(hunk.lines[i]!, lineHtmls[i]!, showLineNumbers);
      }
    }
  }
  if (rows === '') {
    return '';
  }
  return (
    '<pre><code class="hljs"><table class="code-table diff-table">' + rows + '</table></code></pre>'
  );
}

// 左右分割表示のために、ハンクの行を「旧側 / 新側」の対へ畳む。
// 連続する削除と追加は同じ行に並べる(エディタの差分表示と同じ見え方)。
// 返すのは行オブジェクトではなく `hunk.lines` の添字。ハイライト済み HTML を
// 添字で引くため(ハンク単位でまとめてハイライトする方針を崩さない)。
function pairDiffLines(lines: DiffLine[]): DiffLinePair[] {
  var pairs: DiffLinePair[] = [];
  var i = 0;
  while (i < lines.length) {
    if (lines[i]!.type === 'context') {
      pairs.push({ left: i, right: i });
      i += 1;
      continue;
    }
    var dels: number[] = [];
    var adds: number[] = [];
    while (i < lines.length && lines[i]!.type === 'del') {
      dels.push(i);
      i += 1;
    }
    while (i < lines.length && lines[i]!.type === 'add') {
      adds.push(i);
      i += 1;
    }
    var count = Math.max(dels.length, adds.length);
    for (var k = 0; k < count; k++) {
      pairs.push({
        left: k < dels.length ? dels[k]! : null,
        right: k < adds.length ? adds[k]! : null,
      });
    }
  }
  return pairs;
}

// 左右分割の片側 1 マス分(行番号・記号・内容)。行が無い側は空マスで埋める
// (対応する行が無いことを見せるため、行自体を詰めない)。
function diffSideCells(
  line: DiffLine | null,
  lineHtml: string,
  showLineNumbers: boolean | undefined,
  side: 'left' | 'right',
): string {
  var numberClass = side === 'left' ? 'diff-old' : 'diff-new';
  if (line === null) {
    var emptyNumber =
      showLineNumbers === true ? '<td class="line-number ' + numberClass + '"></td>' : '';
    return (
      emptyNumber +
      '<td class="diff-marker diff-empty" aria-hidden="true"></td>' +
      '<td class="line-content diff-empty"></td>'
    );
  }
  var number =
    showLineNumbers === true
      ? '<td class="line-number ' +
        numberClass +
        '">' +
        (side === 'left' ? line.oldNumber : line.newNumber) +
        '</td>'
      : '';
  return (
    number +
    '<td class="diff-marker" aria-hidden="true">' +
    diffMarkerGlyph(line.type) +
    '</td>' +
    lineContentCell(lineHtml)
  );
}

// 左右分割(side-by-side)の差分表示 HTML。インライン表示と同じ code-table 構造・
// 同じハイライト結果を使い、行の並べ方だけが違う。
function renderSideBySideDiffHtml(
  hljs: CodeHighlighter,
  diffText: unknown,
  lang: string | undefined,
  showLineNumbers: boolean | undefined,
): string {
  var files = parseUnifiedDiff(diffText);
  // 外側の diff-split テーブルは 1 行あたり左右 2 セルしか持たない(行番号・記号・
  // 内容は各側の diff-side-table に入る)。区切り行だけ 6 列にすると表全体が 6 列と
  // みなされ、.diff-split .diff-side { width: 50% } が効かず左右のペインが潰れる。
  var span = 2;
  var rows = '';
  for (var f = 0; f < files.length; f++) {
    var hunks = files[f]!.hunks;
    for (var h = 0; h < hunks.length; h++) {
      var hunk = hunks[h]!;
      var lineHtmls = highlightedDiffLines(hljs, hunk, lang);
      if (rows !== '') {
        rows += diffHunkSeparatorRow(span);
      }
      var pairs = pairDiffLines(hunk.lines);
      for (var p = 0; p < pairs.length; p++) {
        var left = pairs[p]!.left;
        var right = pairs[p]!.right;
        var leftClass = left === null ? 'diff-empty' : 'diff-' + hunk.lines[left]!.type;
        var rightClass = right === null ? 'diff-empty' : 'diff-' + hunk.lines[right]!.type;
        rows +=
          '<tr class="diff-line">' +
          '<td class="diff-side diff-side-left ' +
          leftClass +
          '"><table class="diff-side-table"><tr>' +
          diffSideCells(
            left === null ? null : hunk.lines[left]!,
            left === null ? '' : lineHtmls[left]!,
            showLineNumbers,
            'left',
          ) +
          '</tr></table></td>' +
          '<td class="diff-side diff-side-right ' +
          rightClass +
          '"><table class="diff-side-table"><tr>' +
          diffSideCells(
            right === null ? null : hunk.lines[right]!,
            right === null ? '' : lineHtmls[right]!,
            showLineNumbers,
            'right',
          ) +
          '</tr></table></td></tr>';
      }
    }
  }
  if (rows === '') {
    return '';
  }
  return (
    '<pre><code class="hljs"><table class="code-table diff-table diff-split">' +
    rows +
    '</table></code></pre>'
  );
}

// レイアウト名から差分表示 HTML を組み立てる。呼び出し側(renderers.js)が
// レイアウトごとに分岐を持たないよう、選択をここへ閉じる。
function renderDiffHtml(
  hljs: CodeHighlighter,
  diffText: unknown,
  lang: string | undefined,
  showLineNumbers: boolean | undefined,
  layout: string | undefined,
): string {
  return layout === 'side-by-side'
    ? renderSideBySideDiffHtml(hljs, diffText, lang, showLineNumbers)
    : renderInlineDiffHtml(hljs, diffText, lang, showLineNumbers);
}

export {
  parseUnifiedDiff,
  highlightedDiffLines,
  diffMarkerGlyph,
  pairDiffLines,
  renderInlineDiffHtml,
  renderSideBySideDiffHtml,
  renderDiffHtml,
};
export type { DiffLineType, DiffLine, DiffHunk, DiffFile, DiffLinePair };
