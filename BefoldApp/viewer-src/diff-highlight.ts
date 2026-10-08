// 差分ハンクのシンタックスハイライト(旧版・新版を別々にまとめて処理する)。

import { highlightCode, reflowSpanBalancedLines } from './code-html.js';
import type { DiffHunk, DiffLine } from './diff-parse.js';
import { escapeHtml } from './encoding.js';

/// 依存注入される highlight.js の最小インターフェース。code-html.ts が
/// highlightCode に定めているものと同一で、そこから引き写す
/// (同じ形の interface をこちらで二重に定義すると片方だけずれる)。
export type CodeHighlighter = Parameters<typeof highlightCode>[0];

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
    var match = highlighted.match(/^<pre><code[^>]*>([\s\S]*)<\/code><\/pre>$/u);
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
export function highlightedDiffLines(
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
