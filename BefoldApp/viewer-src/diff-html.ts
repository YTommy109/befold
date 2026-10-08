// git 差分表示。unified diff の解析と、インライン/左右分割 2 レイアウトの HTML 組み立て。
// 既存のソース表示と同じ <table class="code-table"> 構造に載せるため、行番号・
// インデントガイド・シンタックスハイライト・検索がそのまま効く。

import { lineContentCell } from './code-html.js';
import { highlightedDiffLines } from './diff-highlight.js';
import type { CodeHighlighter } from './diff-highlight.js';
import {
  assignChangeBlockIndexes,
  nextChangeBlockIndex,
  pairDiffLines,
  parseUnifiedDiff,
} from './diff-parse.js';
import type { DiffLine, DiffLineType, DiffHunk, DiffFile, DiffLinePair } from './diff-parse.js';
import { markWordRanges, wordDiffRanges } from './diff-words.js';
import type { WordRange } from './diff-words.js';

// ハンクの行ごとに、行内で実際に変わった語の強調範囲を求める(TASK-528)。
// 戻り値は必ず hunk.lines と同じ長さで、添字で引ける(highlightedDiffLines と同じ
// 不変条件。長さがずれると呼び出し側が undefined を掴む)。強調しない行は null。
//
// 対応付けは `pairDiffLines` だけを使う。インラインと左右分割がこの 1 本を共有するので、
// 「どの削除行とどの追加行が同じ行の変更か」がレイアウトによって食い違わないことが
// 構造として決まる(行テキストの類似度や DOM の形からは決めない)。
// 対にならなかった行(片側だけの追加・削除)は比較相手が居ないので強調しない。
function wordRangesForHunk(lines: DiffLine[]): (WordRange[] | null)[] {
  var result: (WordRange[] | null)[] = [];
  for (var n = 0; n < lines.length; n++) {
    result.push(null);
  }
  var pairs = pairDiffLines(lines);
  for (var p = 0; p < pairs.length; p++) {
    var left = pairs[p]!.left;
    var right = pairs[p]!.right;
    if (left === null || right === null) {
      continue;
    }
    if (lines[left]!.type !== 'del' || lines[right]!.type !== 'add') {
      continue;
    }
    var ranges = wordDiffRanges(lines[left]!.text, lines[right]!.text);
    if (ranges === null) {
      continue;
    }
    result[left] = ranges.old;
    result[right] = ranges.new;
  }
  return result;
}

// 表へ載せる 1 行分の HTML。ハイライト済みの行に語強調を重ねる。
// 行が無い側(左右分割の空マス)は空文字列。
function diffLineHtml(
  lines: DiffLine[],
  lineHtmls: string[],
  wordRanges: (WordRange[] | null)[],
  index: number | null,
): string {
  if (index === null) {
    return '';
  }
  return markWordRanges(lineHtmls[index]!, lines[index]!.text, wordRanges[index]!);
}

// 行に付ける変更ブロックの属性。文脈行(null)では何も付けない。
// 属性で持たせるのは、インラインと左右分割で行のクラスの付き先が違う
// (インラインは tr、分割は側セル)一方、目印の列挙は同じセレクタで済ませるため。
// 列挙側が DOM の形ではなくこの属性だけを見れば、レイアウトによらず
// 同じ数・同じ順序になることが構造として保証される。
function changeBlockAttribute(blockIndex: number | null | undefined): string {
  if (blockIndex === null || blockIndex === undefined) {
    return '';
  }
  return ' data-diff-block="' + blockIndex + '"';
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
function diffRow(
  line: DiffLine,
  lineHtml: string,
  showLineNumbers: boolean | undefined,
  blockIndex: number | null,
): string {
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
    '"' +
    changeBlockAttribute(blockIndex) +
    '>' +
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
  diffText: string | null | undefined,
  lang: string | undefined,
  showLineNumbers: boolean | undefined,
): string {
  var files = parseUnifiedDiff(diffText);
  var rows = '';
  // 変更ブロックの通し番号。ファイル・ハンクをまたいで続ける。
  var nextBlock = 0;
  for (var f = 0; f < files.length; f++) {
    var hunks = files[f]!.hunks;
    for (var h = 0; h < hunks.length; h++) {
      var hunk = hunks[h]!;
      var lineHtmls = highlightedDiffLines(hljs, hunk, lang);
      var wordRanges = wordRangesForHunk(hunk.lines);
      var blocks = assignChangeBlockIndexes(hunk.lines, nextBlock);
      nextBlock = nextChangeBlockIndex(blocks, nextBlock);
      // 先頭には区切りを置かない(境目が無いところに帯だけが出るため)。
      if (rows !== '') {
        rows += diffHunkSeparatorRow(showLineNumbers === true ? 4 : 2);
      }
      for (var i = 0; i < hunk.lines.length; i++) {
        rows += diffRow(
          hunk.lines[i]!,
          diffLineHtml(hunk.lines, lineHtmls, wordRanges, i),
          showLineNumbers,
          blocks[i] ?? null,
        );
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
  diffText: string | null | undefined,
  lang: string | undefined,
  showLineNumbers: boolean | undefined,
): string {
  var files = parseUnifiedDiff(diffText);
  // 外側の diff-split テーブルは 1 行あたり左右 2 セルしか持たない(行番号・記号・
  // 内容は各側の diff-side-table に入る)。区切り行だけ 6 列にすると表全体が 6 列と
  // みなされ、.diff-split .diff-side { width: 50% } が効かず左右のペインが潰れる。
  var span = 2;
  var rows = '';
  var nextBlock = 0;
  for (var f = 0; f < files.length; f++) {
    var hunks = files[f]!.hunks;
    for (var h = 0; h < hunks.length; h++) {
      var hunk = hunks[h]!;
      var lineHtmls = highlightedDiffLines(hljs, hunk, lang);
      var wordRanges = wordRangesForHunk(hunk.lines);
      var blocks = assignChangeBlockIndexes(hunk.lines, nextBlock);
      nextBlock = nextChangeBlockIndex(blocks, nextBlock);
      if (rows !== '') {
        rows += diffHunkSeparatorRow(span);
      }
      var pairs = pairDiffLines(hunk.lines);
      for (var p = 0; p < pairs.length; p++) {
        var left = pairs[p]!.left;
        var right = pairs[p]!.right;
        var leftClass = left === null ? 'diff-empty' : 'diff-' + hunk.lines[left]!.type;
        var rightClass = right === null ? 'diff-empty' : 'diff-' + hunk.lines[right]!.type;
        // 対の左右は同じブロックに属する(削除の連なりと直後の追加の連なりを
        // 1 ブロックとして数えるため)。どちらか在る方から番号を取る。
        var pairBlock: number | null = (left === null ? blocks[right!] : blocks[left]) ?? null;
        rows +=
          '<tr class="diff-line"' +
          changeBlockAttribute(pairBlock) +
          '>' +
          '<td class="diff-side diff-side-left ' +
          leftClass +
          '"><table class="diff-side-table"><tr>' +
          diffSideCells(
            left === null ? null : hunk.lines[left]!,
            diffLineHtml(hunk.lines, lineHtmls, wordRanges, left),
            showLineNumbers,
            'left',
          ) +
          '</tr></table></td>' +
          '<td class="diff-side diff-side-right ' +
          rightClass +
          '"><table class="diff-side-table"><tr>' +
          diffSideCells(
            right === null ? null : hunk.lines[right]!,
            diffLineHtml(hunk.lines, lineHtmls, wordRanges, right),
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
  diffText: string | null | undefined,
  lang: string | undefined,
  showLineNumbers: boolean | undefined,
  layout: string | undefined,
): string {
  return layout === 'side-by-side'
    ? renderSideBySideDiffHtml(hljs, diffText, lang, showLineNumbers)
    : renderInlineDiffHtml(hljs, diffText, lang, showLineNumbers);
}

export {
  assignChangeBlockIndexes,
  parseUnifiedDiff,
  highlightedDiffLines,
  diffMarkerGlyph,
  pairDiffLines,
  renderInlineDiffHtml,
  renderSideBySideDiffHtml,
  renderDiffHtml,
  wordRangesForHunk,
};
export type { DiffLineType, DiffLine, DiffHunk, DiffFile, DiffLinePair };
