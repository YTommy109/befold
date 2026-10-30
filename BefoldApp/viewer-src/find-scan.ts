// 検索のスキャン: クエリから RegExp を組み立て、#diagram-wrap 配下のテキストを走査して
// 一致位置を StaticRange として返す。描画は CSS Custom Highlight API（find-highlight.ts）で
// 行い、DOM は一切書き換えない（最低対応 macOS 14.2 の WebKit には常に API がある。TASK-902）。

import { setNativeHighlights } from './find-highlight.js';

// 検索の 3 トグル。window._mmdInitialFindOptions（Swift が注入する側、すべて省略可）と
// 違い、コントローラ内部では 3 つとも常に確定している。
export interface FindOptions {
  caseSensitive: boolean;
  wholeWord: boolean;
  useRegex: boolean;
}

interface SearchScope {
  nodes: Text[];
  starts: number[];
  text: string;
}

// 毎打鍵の DOM 走査と検索テキスト再構築を避け、refresh/invalidate/close で索引を破棄する。
var indexedScopes: SearchScope[] | null = null;

export function clearFindCache(): void {
  indexedScopes = null;
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

// 連結文字列上のオフセットから、境界に使うテキストノードの添字を逆引きする。
// textNodes[i] は連結文字列上で [starts[i], starts[i] + textNodes[i].length) を占める。
//
// ノードの継ぎ目ちょうどのオフセット(前ノードの終端 === 次ノードの先頭)は
// DOM 上は同じ位置を指すが、開始側は次ノードの先頭(offset 0)、終了側は前ノードの
// 終端を使い、範囲が実際にはマッチしていない隣接ノードへ食み出さないようにする
// (isStart=true: 継ぎ目では後方のノードを優先。isStart=false: 前方のノードを優先)。
// starts は textNodes と同じ長さで同時に構築される（matchScope 参照）ため、
// 走査中の添字と末尾要素は必ず存在する。noUncheckedIndexedAccess 下で
// undefined が付くのを非 null 表明で落としている（実行時の判定は変えていない）。
function locate(scope: SearchScope, offset: number, isStart: boolean, low = 0): number {
  // 密なヒットは直前か次のノードにあるため先に試し、離れた一致だけ二分探索する。
  var high = scope.nodes.length;
  var end = scope.starts[low + 1] ?? scope.text.length;
  if (isStart ? offset < end : offset <= end) return low;
  low++;
  if (low < high) {
    end = scope.starts[low + 1] ?? scope.text.length;
    if (isStart ? offset < end : offset <= end) return low;
    low++;
  }
  while (low < high) {
    var middle = Math.floor((low + high) / 2);
    end = scope.starts[middle + 1] ?? scope.text.length;
    if (isStart ? offset < end : offset <= end) high = middle;
    else low = middle + 1;
  }
  return Math.min(low, scope.nodes.length - 1);
}

// SVG(mermaid の描画結果)・STYLE・SCRIPT 配下は再帰しない。STYLE / SCRIPT の中身は
// 表示されない文字列で、mermaid 図のラベル文字列(SVG text)も検索対象外とする
// (SVG の扱いは TASK-902 の Notes を参照)。
//
// 注意: DOM 仕様上 Element.tagName が ASCII 大文字化されるのは HTML 名前空間の要素の
// みで、SVG 名前空間の要素(mermaid が描画する <svg>/<text>/<tspan> や注入する
// <style> を含む)の tagName は大文字化されず小文字のまま返る(例: 'svg'、'style')。
// このリストは大文字で保持しつつ、比較側で toUpperCase() して正規化する。
var skipTags = ['SVG', 'STYLE', 'SCRIPT'];

// 図のズーム操作（zoom.ts が #diagram-wrap の中に置く「− 100% ＋」）は文書の内容では
// ない。倍率が変わると label のテキストノードが差し替わり、索引が切り離されたノードを
// 指したままになるので、索引にも検索対象にも入れない。
var skipClass = 'diagram-zoom-controls';

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
  'MARK',
];

function isBridgeable(node: Node): boolean {
  return node instanceof Element && bridgeTags.includes(node.tagName.toUpperCase());
}

// #diagram-wrap 配下(skipTags 除く)を再帰し、bridgeTags で連結できる範囲だけを
// 1つの「スコープ」(テキストノードの配列)としてまとめる。見出し・段落・リスト
// 項目・テーブル行/セルなど bridgeTags 以外の要素に出会うたびにスコープを区切る
// ことで、シンタックスハイライトの <span> 境界はまたぎつつ、行番号付きコード
// ブロックの <tr>/<td> のような構造上の境界はまたがないようにする(セルや行を
// またいだ一致は、利用者にとって 1 続きの文字列ではないため)。
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
      } else if (
        child instanceof Element &&
        !skipTags.includes(child.tagName.toUpperCase()) &&
        !child.classList.contains(skipClass)
      ) {
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
// 位置を (textNode, localOffset) に逆引きして StaticRange の初期値にする。
// ゼロ幅マッチ(例: 正規表現 "a*" の空文字一致)は無限ループを避けるため読み飛ばす。
function matchScope(scope: SearchScope, regex: RegExp, found: StaticRangeInit[]): void {
  var text = scope.text;
  regex.lastIndex = 0;
  var match: RegExpExecArray | null;
  // 非空の一致は順番に来るため、前の終了ノードから次の開始を探せる。
  var nodeIndex = 0;
  while ((match = regex.exec(text)) !== null) {
    if (match[0].length === 0) {
      regex.lastIndex++;
      if (regex.lastIndex > text.length) break;
      continue;
    }
    var start = locate(scope, match.index, true, nodeIndex);
    var end = locate(scope, match.index + match[0].length, false, start);
    nodeIndex = end;
    found.push({
      startContainer: scope.nodes[start]!,
      startOffset: match.index - scope.starts[start]!,
      endContainer: scope.nodes[end]!,
      endOffset: match.index + match[0].length - scope.starts[end]!,
    });
  }
}

// #diagram-wrap 配下をスコープ(bridgeTags でつながった範囲)に分割し、スコープ
// ごとにマッチさせる。一致は document 順に並べて返し、そのままハイライトに登録する。
export function walk(root: Node, regex: RegExp): StaticRangeInit[] {
  var found: StaticRangeInit[] = [];
  indexedScopes ??= collectScopes(root).map((nodes) => indexScope(nodes));
  indexedScopes.forEach(function (scope) {
    matchScope(scope, regex, found);
  });
  setNativeHighlights(root, found);
  return found;
}
