// Markdown のレンダリング表示に git 差分を重ねる(TASK-483.4)。
// 設計: docs/superpowers/specs/2026-11-21-rendered-markdown-diff-design.md
//
// 旧版・新版をそれぞれ markdown-it で parse し、トップレベルのブロックを単位にして
// token.map(ソース行の範囲)で差分の行を引き当てる。削除ブロックも描いて削除色を付け、
// 追加ブロックとともに文書順に並べる(並べ替えは CSV と共通の orderDiffUnits)。

import { orderDiffUnits, wholeFileDiffSides } from './diff-units.js';
import { markdownRenderer, sanitizeRenderedHtml } from './markdown.js';
import { DOMPurify } from './vendor.js';

type MarkdownTokens = ReturnType<ReturnType<typeof markdownRenderer>['parse']>;

/// 1 版分の parse 結果。blocks[i] はトップレベルのブロック i のトークン範囲 [start, end)。
interface ParsedSide {
  tokens: MarkdownTokens;
  env: object;
  blocks: [number, number][];
  ranges: [number, number][];
}

// トップレベル(level 0)の開きトークンから、対応する閉じトークンまでを 1 ブロックにする。
// fence・hr・html_block のように開閉を持たないブロックはトークン 1 つで 1 ブロック。
// map を持たないトークン(ソース行に対応しない)はブロックにしない。
function parseSide(text: string): ParsedSide {
  var env = {};
  var tokens = markdownRenderer().parse(text, env);
  var blocks: [number, number][] = [];
  var ranges: [number, number][] = [];
  var i = 0;
  while (i < tokens.length) {
    var start = i;
    var depth = 0;
    do {
      depth += tokens[i]!.nesting;
      i++;
    } while (depth > 0 && i < tokens.length);
    var map = tokens[start]!.map;
    if (map) {
      blocks.push([start, i]);
      ranges.push([map[0], map[1]]);
    }
  }
  return { tokens: tokens, env: env, blocks: blocks, ranges: ranges };
}

// サニタイズは連結した全体に 1 回だけかける。ブロックごとにかけると、ブロックを
// またぐ HTML(<details> の開きと閉じが別ブロックにある等)がブロックの中で閉じられ、
// 通常のレンダリング表示(⌘1)と違う形になる。
function renderBlock(side: ParsedSide, index: number): string {
  var md = markdownRenderer();
  var block = side.blocks[index]!;
  return md.renderer.render(side.tokens.slice(block[0], block[1]), md.options, side.env);
}

// 旧版のトークンから id を外す。見出しのアンカーと見出しジャンプが新版の見出しを
// 指すようにするため(旧版の見出しは同じ slug で二重に現れる)。
function stripIds(side: ParsedSide): ParsedSide {
  side.tokens.forEach(function (token) {
    if (token.attrs) token.attrs = token.attrs.filter((attr) => attr[0] !== 'id');
  });
  return side;
}

// 差分から Markdown の描画 HTML を組む。描けない差分では null を返し、
// 呼び出し側が通常のレンダリング表示へ落とす。
function buildMarkdownDiffHtml(diffText: string): string | null {
  var sides = wholeFileDiffSides(diffText);
  if (sides === null) {
    return null;
  }
  var oldSide = stripIds(parseSide(sides.oldText));
  var newSide = parseSide(sides.newText);
  var units = orderDiffUnits(sides.lines, oldSide.ranges, newSide.ranges);
  var html = units
    .map(function (unit) {
      var block = renderBlock(unit.side === 'old' ? oldSide : newSide, unit.index);
      if (unit.type === 'context') {
        return block;
      }
      return (
        '<div class="md-diff-block diff-' +
        unit.type +
        '" data-diff-block="' +
        unit.block +
        '">' +
        block +
        '</div>'
      );
    })
    .join('');
  return sanitizeRenderedHtml(DOMPurify, html);
}

export { buildMarkdownDiffHtml };
