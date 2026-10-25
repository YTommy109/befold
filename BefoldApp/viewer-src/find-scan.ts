// 検索のスキャンとハイライト。対応する WebKit では DOM を変えずに描画する。

import { clearNativeHighlights, setNativeHighlights } from './find-highlight.js';

// 検索の 3 トグル。window._mmdInitialFindOptions（Swift が注入する側、すべて省略可）と
// 違い、コントローラ内部では 3 つとも常に確定している。
export interface FindOptions {
  caseSensitive: boolean;
  wholeWord: boolean;
  useRegex: boolean;
}

// 連結文字列上のオフセットの逆引き結果（locate の戻り値）。
// Array.prototype.toReversed は Safari 17（WKWebView）に実装済みだが、tsconfig の
// lib が ES2022 のため型定義に無い（ES2023 で追加）。実行時の振る舞いを変えたくないので
// slice().reverse() へは書き換えず、型だけをここで補う。
// lib を ES2023 へ上げれば不要になる（tsconfig.json は他エージェントと共用のため触っていない）。
declare global {
  interface Array<T> {
    toReversed(): T[];
  }
}

export type FindMatch = HTMLElement | StaticRangeInit;

function supportsHighlights(): boolean {
  return (
    typeof CSS !== 'undefined' &&
    !!CSS.highlights &&
    typeof Highlight !== 'undefined' &&
    typeof StaticRange !== 'undefined'
  );
}

interface SearchScope {
  nodes: Text[];
  starts: number[];
  text: string;
}

var usingNativeHighlights = false;
// render/append clear this through Find.refresh; typing reuses the same document.
var indexedScopes: SearchScope[] | null = null;

export function clearFindCache(): void {
  indexedScopes = null;
}

// Rendering will replace the DOM, so discard ranges without unwrapping legacy marks.
export function invalidateFindDocument(): void {
  if (usingNativeHighlights) {
    clearNativeHighlights();
    usingNativeHighlights = false;
  }
  clearFindCache();
}

function indexScope(nodes: Text[]): SearchScope {
  var starts: number[] = [];
  var text = '';
  nodes.forEach(function (node) {
    starts.push(text.length);
    text += node.textContent!;
  });
  return { nodes: nodes, starts: starts, text: text };
}

interface TextLocation {
  node: Text;
  localOffset: number;
}

// クエリと3トグル(caseSensitive / wholeWord / useRegex)から RegExp を組み立てる。
// クエリが空、または正規表現として不正な場合は null を返す(呼び出し側はエラー表示に切り替える)。
export function buildFindRegExp(query: string, options: FindOptions): RegExp | null {
  if (!query) {
    return null;
  }
  var source = options.useRegex ? query : query.replaceAll(/[.*+?^${}()|[\]\\]/gu, '\\$&');
  if (options.wholeWord) {
    source = '\\b(?:' + source + ')\\b';
  }
  var flags = 'g' + (options.caseSensitive ? '' : 'i');
  try {
    return new RegExp(source, flags);
  } catch (e) {
    return null;
  }
}

// 前回のハイライトを解除する(次の検索前に必ず呼ぶ)。
// Custom Highlight API が無い WebKit では従来の <mark> を復元する。
// span 境界をまたぐマッチは <mark> の中に元の <span> 構造を保持したまま挿入して
// いるため、単純に textContent で潰すとシンタックスハイライトの構造が壊れる。
// mark を子ノードで置き換える(unwrap)ことで元の構造を保ったまま平文表示に戻す。
// normalize() は親ごとに1回だけ呼ぶ(同じ親に複数の <mark> がある場合の重複呼び出しを避ける)。
export function clearMarks() {
  if (usingNativeHighlights) {
    clearNativeHighlights();
    usingNativeHighlights = false;
    return;
  }
  var marks = document.querySelectorAll('#diagram-wrap mark.mmd-find-match');
  var parents = new Set<Node>();
  marks.forEach(function (mark) {
    var parent = mark.parentNode;
    if (!parent) return;
    while (mark.firstChild) {
      parent.insertBefore(mark.firstChild, mark);
    }
    mark.remove();
    parents.add(parent);
  });
  parents.forEach(function (parent) {
    parent.normalize();
  });
}
// 連結文字列上のオフセットを (テキストノード, ノード内オフセット) に逆引きする。
// textNodes[i] は連結文字列上で [starts[i], starts[i] + textNodes[i].length) を占める。
//
// ノードの継ぎ目ちょうどのオフセット(前ノードの終端 === 次ノードの先頭)は
// DOM 上は同じ位置を指すが、Range の「祖先を完全に含むか」の判定はどちらの
// ノードを境界に使うかで変わる。開始側は次ノードの先頭(offset 0)、終了側は
// 前ノードの終端を使わないと、実際にはマッチしていない隣接 <span> まで
// 「部分的に含む」扱いになり、意図せず分割・複製されてしまう
// (isStart=true: 継ぎ目では後方のノードを優先。isStart=false: 前方のノードを優先)。
// starts は textNodes と同じ長さで同時に構築される（matchScope 参照）ため、
// 走査中の添字と末尾要素は必ず存在する。noUncheckedIndexedAccess 下で
// undefined が付くのを非 null 表明で落としている（実行時の判定は変えていない）。
function locate(scope: SearchScope, offset: number, isStart: boolean): TextLocation {
  // Use cached numeric boundaries; DOM length reads per hit cost more than the regex itself.
  var low = 0;
  var high = scope.nodes.length;
  while (low < high) {
    var middle = Math.floor((low + high) / 2);
    var end = scope.starts[middle + 1] ?? scope.text.length;
    if (isStart ? offset < end : offset <= end) high = middle;
    else low = middle + 1;
  }
  var index = Math.min(low, scope.nodes.length - 1);
  return { node: scope.nodes[index]!, localOffset: offset - scope.starts[index]! };
}

// node から祖先方向へ、内容が空になった要素を取り除く(root には触れない)。
// extractContents() は境界の Text ノードを削除せず長さ0のまま残すため、
// hasChildNodes() ではなく textContent で空判定する。
function pruneEmptyAncestors(node: Node | null, root: Node): void {
  while (node && node !== root && node instanceof Element && node.textContent === '') {
    var parent: Node | null = node.parentNode;
    if (!parent) break;
    node.remove();
    node = parent;
  }
}

// SVG(mermaid の描画結果)・STYLE・SCRIPT 配下は再帰しない: SVG 名前空間に HTML の
// <mark> を挿入すると描画されず文字が消え、mermaid が注入する <style> の中身を
// 誤ってラップすると図のスタイルも壊れるため。この結果、mermaid 図のラベル文字列
// (SVG text)は検索対象外となるが、これは意図したスコープ境界であり見落としではない。
//
// 注意: DOM 仕様上 Element.tagName が ASCII 大文字化されるのは HTML 名前空間の要素の
// みで、SVG 名前空間の要素(mermaid が描画する <svg>/<text>/<tspan> や注入する
// <style> を含む)の tagName は大文字化されず小文字のまま返る(例: 'svg'、'style')。
// このリストは大文字で保持しつつ、比較側で toUpperCase() して正規化する。
var skipTags = ['MARK', 'SVG', 'STYLE', 'SCRIPT'];

// マッチをまたいでよい(連結対象の)インライン要素。シンタックスハイライトの
// <span> やパス参照・通常リンクの <a>、Markdown の強調表現などはトークンを
// 分割するだけで論理的には1つの地の文なので、テキストノードを連結してよい。
// 見出し・段落・リスト項目・テーブル行/セルなど、ここに挙げていない要素は
// すべて「またいではいけない境界」として扱う(collectScopes 参照)。
var bridgeTags = [
  'SPAN',
  'A',
  'CODE',
  'EM',
  'STRONG',
  'B',
  'I',
  'U',
  'S',
  'DEL',
  'INS',
  'SMALL',
  'SUB',
  'SUP',
  'ABBR',
  'KBD',
  'SAMP',
  'VAR',
  'Q',
  'CITE',
  'TIME',
  'LABEL',
];

function isBridgeable(node: Node): boolean {
  return node instanceof Element && bridgeTags.includes(node.tagName.toUpperCase());
}

// #diagram-wrap 配下(skipTags 除く)を再帰し、bridgeTags で連結できる範囲だけを
// 1つの「スコープ」(テキストノードの配列)としてまとめる。見出し・段落・リスト
// 項目・テーブル行/セルなど bridgeTags 以外の要素に出会うたびにスコープを区切る
// ことで、シンタックスハイライトの <span> 境界はまたぎつつ、行番号付きコード
// ブロックの <tr>/<td> のような構造上の境界はまたがないようにする(またぐと
// Range.extractContents() がテーブル構造を破壊してレイアウトが崩れる)。
// スコープはすべて document 順で返す。
function collectScopes(root: Node): Text[][] {
  var scopes: Text[][] = [];
  var current: Text[] = [];
  function flush(): void {
    if (current.length > 0) {
      scopes.push(current);
      current = [];
    }
  }
  function recurse(node: Node): void {
    var children = node.childNodes;
    for (var i = 0; i < children.length; i++) {
      var child = children[i]!;
      if (child instanceof Text) {
        current.push(child);
      } else if (child instanceof Element && !skipTags.includes(child.tagName.toUpperCase())) {
        if (isBridgeable(child)) {
          recurse(child);
        } else {
          flush();
          recurse(child);
          flush();
        }
      }
    }
  }
  recurse(root);
  flush();
  return scopes;
}

// 1スコープ(bridgeTags でつながった範囲)のテキストを連結してマッチさせ、マッチ
// 位置を (textNode, localOffset) に逆引きして StaticRange（旧 WebKit は <mark>）にする。
// ゼロ幅マッチ(例: 正規表現 "a*" の空文字一致)は無限ループを避けるため読み飛ばす。
function matchScope(
  root: Node,
  scope: SearchScope,
  regex: RegExp,
  found: HTMLElement[],
  domRange: Range | null,
  nativeMatches: StaticRangeInit[] | null,
): void {
  var text = scope.text;
  regex.lastIndex = 0;
  var ranges: { start: number; end: number }[] = [];
  var match: RegExpExecArray | null;
  while ((match = regex.exec(text)) !== null) {
    if (match[0].length === 0) {
      regex.lastIndex++;
      if (regex.lastIndex > text.length) break;
      continue;
    }
    if (nativeMatches) {
      var nativeStart = locate(scope, match.index, true);
      var nativeEnd = locate(scope, match.index + match[0].length, false);
      nativeMatches.push({
        startContainer: nativeStart.node,
        startOffset: nativeStart.localOffset,
        endContainer: nativeEnd.node,
        endOffset: nativeEnd.localOffset,
      });
    } else {
      ranges.push({ start: match.index, end: match.index + match[0].length });
    }
  }
  if (nativeMatches || !domRange || ranges.length === 0) return;

  var scopeFound: HTMLElement[] = [];
  // Range 構築中に DOM を書き換えるとテキストノードがずれるため、末尾側から処理する。
  ranges.toReversed().forEach(function (range) {
    var start = locate(scope, range.start, true);
    var end = locate(scope, range.end, false);
    // extractContents() は境界をまたぐマッチの端で、部分的にしか含まれない祖先要素
    // (例: <span>foo</span> の "foo" 全体が対象でも境界が offset 0 なので「完全に
    // 含まれる」扱いにならない)を空のまま DOM に残す。参照はここで取っておき、
    // 抽出後に空になっていれば取り除く(そうしないと再検索のたびに空 <span> が
    // 増殖し、シンタックスハイライトの構造が壊れていく)。
    var startAncestor: Node | null = start.node.parentNode;
    var endAncestor: Node | null = end.node.parentNode;
    domRange.setStart(start.node, start.localOffset);
    domRange.setEnd(end.node, end.localOffset);

    var mark = document.createElement('mark');
    mark.className = 'mmd-find-match';
    mark.append(domRange.extractContents());
    domRange.insertNode(mark);
    scopeFound.push(mark);

    pruneEmptyAncestors(startAncestor, root);
    pruneEmptyAncestors(endAncestor, root);
  });
  for (var i = scopeFound.length - 1; i >= 0; i--) found.push(scopeFound[i]!);
}

// #diagram-wrap 配下をスコープ(bridgeTags でつながった範囲)に分割し、スコープ
// ごとにマッチさせる。document 順のまま found に積む。
export function walk(root: Node, regex: RegExp): FindMatch[] {
  // ヒットごとに生成すると、GC まで残る live Range の境界更新が DOM 操作のたびに走る。
  // WebKit で大量ヒット時に入力が固まるため、検索全体で1つを使い回す。
  usingNativeHighlights =
    supportsHighlights() &&
    root instanceof Element &&
    root.matches('.csv-body, .code-body:has(code.csv-source)');
  var nativeMatches: StaticRangeInit[] | null = usingNativeHighlights ? [] : null;
  var found: HTMLElement[] = [];
  var domRange = nativeMatches ? null : document.createRange();
  var scopes = nativeMatches
    ? (indexedScopes ??= collectScopes(root).map((nodes) => indexScope(nodes)))
    : collectScopes(root).map((nodes) => indexScope(nodes));
  scopes.forEach(function (scope) {
    matchScope(root, scope, regex, found, domRange, nativeMatches);
  });
  if (nativeMatches) {
    setNativeHighlights(root, nativeMatches);
    return nativeMatches;
  }
  return found;
}
