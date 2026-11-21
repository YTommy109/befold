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

// 生 HTML のタグの開きと閉じの差(開き − 閉じ)。空要素(<br> など)と自己終了タグは数えない。
// コメント(<!-- -->)は先頭が英字でないので一致しない。
var VOID_ELEMENTS = new Set([
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'source',
  'track',
  'wbr',
]);
var HTML_TAG = /<(\/?)([A-Za-z][\w-]*)\b[^>]*?(\/?)>/gu;

function htmlDepthDelta(html: string): number {
  var delta = 0;
  for (var match of html.matchAll(HTML_TAG)) {
    if (match[3] === '/' || VOID_ELEMENTS.has(match[2]!.toLowerCase())) continue;
    delta += match[1] === '/' ? -1 : 1;
  }
  return delta;
}

// トップレベル(level 0)の開きトークンから、対応する閉じトークンまでを 1 ブロックにする。
// fence・hr・html_block のように開閉を持たないブロックはトークン 1 つで 1 ブロック。
// map を持たないトークン(ソース行に対応しない)はブロックにしない。
//
// 生 HTML の開きと閉じが別ブロックにある場合(<details> … </details>、
// <div align="center"> … </div>)は、閉じるまでのブロックを 1 単位にまとめる。
// 開きタグだけのブロックを差分の <div> で包むと、包みの </div> の位置で中の要素まで
// 閉じられ、通常の表示(⌘1)と入れ子が変わるため。
function parseSide(text: string): ParsedSide {
  var env = {};
  var tokens = markdownRenderer().parse(text, env);
  var blocks: [number, number][] = [];
  var ranges: [number, number][] = [];
  var openHtml = 0;
  var i = 0;
  while (i < tokens.length) {
    var start = i;
    var depth = 0;
    do {
      depth += tokens[i]!.nesting;
      i++;
    } while (depth > 0 && i < tokens.length);
    var map = tokens[start]!.map;
    if (!map) continue;
    var last = blocks.length - 1;
    if (openHtml > 0 && last >= 0) {
      blocks[last]![1] = i;
      ranges[last]![1] = map[1];
    } else {
      blocks.push([start, i]);
      ranges.push([map[0], map[1]]);
    }
    for (var t = start; t < i; t++) {
      if (tokens[t]!.type === 'html_block') openHtml += htmlDepthDelta(tokens[t]!.content);
    }
    openHtml = Math.max(openHtml, 0);
  }
  return { tokens: tokens, env: env, blocks: blocks, ranges: ranges };
}

function renderBlock(side: ParsedSide, index: number): string {
  var md = markdownRenderer();
  var block = side.blocks[index]!;
  return md.renderer.render(side.tokens.slice(block[0], block[1]), md.options, side.env);
}

// 削除単位の中の id / name を外す。ページ内リンク(getElementById / [name=…])と
// 見出しジャンプが、先に並ぶ削除側の写しではなく新版を指すようにするため。
// 生 HTML の id も対象にするので、描いた HTML の上で外す。単位は生 HTML の開閉が
// 揃うようにまとめてあるので、単位ごとに解析しても入れ子は変わらない。
function withoutAnchors(html: string): string {
  var doc = new DOMParser().parseFromString(html, 'text/html');
  doc.querySelectorAll('[id], [name]').forEach(function (el) {
    el.removeAttribute('id');
    el.removeAttribute('name');
  });
  return doc.body.innerHTML;
}

// 差分から Markdown の描画 HTML を組む。描けない差分では null を返し、
// 呼び出し側が通常のレンダリング表示へ落とす。
function buildMarkdownDiffHtml(diffText: string): string | null {
  var sides = wholeFileDiffSides(diffText);
  if (sides === null) {
    return null;
  }
  var oldSide = parseSide(sides.oldText);
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
        (unit.type === 'del' ? withoutAnchors(block) : block) +
        '</div>'
      );
    })
    .join('');
  // サニタイズは連結した全体に 1 回だけかける(通常の表示と同じ経路)。
  return sanitizeRenderedHtml(DOMPurify, html);
}

export { buildMarkdownDiffHtml };
