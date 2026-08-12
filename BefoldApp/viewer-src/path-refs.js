// 本文中のファイルパス参照を見つけて注釈し、Swift へ解決を依頼して結果を反映する。

import { _MSG_RESOLVE_REFERENCES, _mmdPostMessage, isHostFeatureEnabled } from './bridge.js';

// href がローカルパス候補か。#アンカー・http(s) 等スキーム付きは除外する。
// file.md:12 が scheme="file.md" と誤解釈される都合、ドットを含むスキームは許可する。
function isLocalPathHref(href) {
  if (!href) { return false; }
  if (href.charAt(0) === '#') { return false; }
  var m = href.match(/^([a-zA-Z][a-zA-Z0-9+.\-]*):/);
  if (m && m[1].indexOf('.') === -1) { return false; } // http:, mailto:, tel: 等
  return true;
}

// コードブロック内のファイルパス検出用の正規表現。
// シンタックスハイライトでトークンが複数の <span> に分割されていても、
// 注釈は「単位」(下記)のテキスト全体に対して一致を取るため境界をまたげる。
var _PATH_RE = /(?:(?<![/\w.])(?:\/?\.\.?\/[\w./-]+|[\w.-]+\/[\w./-]+)|(?:^|(?<=\s))\/[\w./-]+)(?:\.(?:swift|md|mmd|ts|tsx|js|jsx|py|rb|go|rs|java|kt|c|cpp|h|hpp|json|yaml|yml|toml|txt|html|css|sh))(?::\d+)*/g;

// パス検出の対象にするタグ(このタグに入った時点で配下は許可状態になる)。
// code はコードブロック(pre 配下)・インラインコードの両方を兼ねる。
var _PATH_ANNOTATE_TAGS = ['p', 'li', 'td', 'th', 'blockquote', 'dt', 'dd', 'code'];

function _annotatePathRefs() {
  var wrap = document.getElementById('diagram-wrap');
  if (wrap) { _walkTextNodes(wrap, false); }
}

// 走査対象外の要素。<a> 配下は既にリンクとして処理済み、svg/.mermaid は
// 図中テキストの誤検出防止、.befold-path-ref 配下は既存ガード(二重ラップ防止)。
function _isSkippedElement(el) {
  var tag = el.tagName.toLowerCase();
  return tag === 'a' || tag === 'svg' || el.classList.contains('mermaid') ||
         el.classList.contains('befold-path-ref');
}

// #diagram-wrap 配下を一度だけ再帰的に歩き、_PATH_ANNOTATE_TAGS の要素を
// 「注釈の単位」として処理する。allowed は呼び出し元が既に対象コンテキスト内に
// いるか(= node 自身を単位として扱うか)を表す。外部からの呼び出しは常に false。
//
// 単位は最も内側の対象タグにする。ソース表示は <pre><code><table> の各行が
// <td class="line-content"> なので、単位は 1 行になる。<code> 全体を 1 単位に
// すると行の境界に区切り文字が無く、前行末と次行頭がつながって誤検出になる。
function _walkTextNodes(node, allowed) {
  if (node.nodeType === 3) { // TEXT_NODE
    if (allowed) { _annotateTextNodes([node]); }
    return;
  }
  if (node.nodeType !== 1) { return; }
  if (_isSkippedElement(node)) { return; }
  var tag = node.tagName.toLowerCase();
  // <pre> 直下のテキストは対象外(markdown-it の html:true により <code> を伴わない
  // 生の <pre> がリスト項目内などに書かれた場合でも誤って対象化しないよう、
  // 祖先から引き継いだ allowed をリセットする)。内側の <code> は改めて単位になるため、
  // 従来の「pre code のみ対象」という範囲はそのまま維持される。
  if (tag === 'pre') {
    _walkChildren(node, false);
    return;
  }
  if (allowed || _PATH_ANNOTATE_TAGS.indexOf(tag) !== -1) {
    _annotateUnit(node);
    return;
  }
  _walkChildren(node, allowed);
}

// スナップショットを取り順方向に走査(replaceChild で兄弟が変わるため)。
function _walkChildren(node, allowed) {
  var children = Array.prototype.slice.call(node.childNodes);
  for (var i = 0; i < children.length; i++) {
    _walkTextNodes(children[i], allowed);
  }
}

// 単位となる要素配下のテキストをまとめて注釈する。ハイライトの <span> で
// 分割されたパスも、単位のテキストとしては連続しているため検出できる。
function _annotateUnit(el) {
  var nodes = [];
  _collectUnitTextNodes(el, nodes);
  _annotateTextNodes(nodes);
}

// 単位に属するテキストノードを集める。入れ子の対象タグ(表の <td>、段落内の
// インライン <code> 等)と <pre> はそれぞれ別の単位として扱い、ここでは集めない。
function _collectUnitTextNodes(node, out) {
  var children = Array.prototype.slice.call(node.childNodes);
  for (var i = 0; i < children.length; i++) {
    var child = children[i];
    if (child.nodeType === 3) {
      out.push(child);
      continue;
    }
    if (child.nodeType !== 1) { continue; }
    if (_isSkippedElement(child)) { continue; }
    var tag = child.tagName.toLowerCase();
    if (tag === 'pre' || _PATH_ANNOTATE_TAGS.indexOf(tag) !== -1) {
      _walkTextNodes(child, false);
      continue;
    }
    _collectUnitTextNodes(child, out);
  }
}

// 連続する 1 本のテキストとみなしたノード列に対してパスを検出し、
// 一致範囲をノードごとの区間へ割り戻して <span class="befold-path-ref"> で包む。
// ノードをまたぐ一致は片ごとに span を作り、どの片も data-path にパス全体を持つ
// (ハイライトの span 構造を壊さずに、どこをクリックしても同じパスが開く)。
function _annotateTextNodes(nodes) {
  if (!nodes.length) { return; }
  var text = '';
  var starts = [];
  for (var i = 0; i < nodes.length; i++) {
    starts.push(text.length);
    text += nodes[i].textContent;
  }
  _PATH_RE.lastIndex = 0;
  var segments = null;
  var match;
  while ((match = _PATH_RE.exec(text)) !== null) {
    var from = match.index;
    var to = from + match[0].length;
    for (var n = 0; n < nodes.length; n++) {
      var nodeStart = starts[n];
      var nodeEnd = nodeStart + nodes[n].textContent.length;
      if (nodeEnd <= from || nodeStart >= to) { continue; }
      if (!segments) { segments = {}; }
      if (!segments[n]) { segments[n] = []; }
      segments[n].push({
        start: Math.max(from, nodeStart) - nodeStart,
        end: Math.min(to, nodeEnd) - nodeStart,
        path: match[0],
      });
    }
  }
  if (!segments) { return; }
  // 一致をすべて求めてから置換する(置換で他ノードのオフセットが動かないよう)。
  for (var key in segments) {
    _replaceWithSegments(nodes[key], segments[key]);
  }
}

// 1 つのテキストノードを、指定区間だけ span で包んだ断片列に置き換える。
function _replaceWithSegments(node, segments) {
  var text = node.textContent;
  var frag = document.createDocumentFragment();
  var lastIndex = 0;
  for (var i = 0; i < segments.length; i++) {
    var seg = segments[i];
    if (seg.start > lastIndex) {
      frag.appendChild(document.createTextNode(text.slice(lastIndex, seg.start)));
    }
    var span = document.createElement('span');
    span.className = 'befold-path-ref';
    span.dataset.path = seg.path;
    span.textContent = text.slice(seg.start, seg.end);
    frag.appendChild(span);
    lastIndex = seg.end;
  }
  if (lastIndex < text.length) {
    frag.appendChild(document.createTextNode(text.slice(lastIndex)));
  }
  node.parentNode.replaceChild(frag, node);
}

// --- 表示時のパス参照解決 ---
// 解決要求を出した順に、その要求に含めた要素をバッチとして積むキュー。
// Swift 側は受信したメッセージごとに必ず 1 回 _mmdApplyResolvedReferences() を
// 評価し、その順序はメインスレッド上で保たれるため、先入れ先出しで
// 「応答 ↔ その応答が答えている要素集合」を対応づけられる。
var _mmdPendingRefBatches = [];

// 分類済み(pending/解決済み/解決失敗)の参照は再収集しない。
function _mmdIsClassifiedRef(el) {
  return el.classList.contains('befold-link-pending') ||
         el.classList.contains('befold-link') ||
         el.classList.contains('befold-link-dead');
}

// 描画直後に呼ぶ。未分類のローカルパス候補(<a> と .befold-path-ref)を集めて
// 一意なパス集合を Swift へ送り、同時に中立化(pending)する。
// 解決が返るまでリンクに見せないことで、開けない偽リンクを出さない。
function _mmdResolveReferences() {
  if (!isHostFeatureEnabled(window._mmdHostFeatures, 'referenceActivation')) { return; }
  var wrap = document.getElementById('diagram-wrap');
  if (!wrap) { return; }
  var targets = [];
  wrap.querySelectorAll('a[href]').forEach(function(a) {
    if (_mmdIsClassifiedRef(a)) { return; }
    var href = a.getAttribute('href');
    if (isLocalPathHref(href)) { targets.push({ el: a, raw: href }); }
  });
  wrap.querySelectorAll('.befold-path-ref').forEach(function(s) {
    if (_mmdIsClassifiedRef(s) || !s.dataset.path) { return; }
    targets.push({ el: s, raw: s.dataset.path });
  });
  if (!targets.length) { return; }
  // プロトタイプを持たない辞書にする。素の {} だと __proto__ への代入が
  // プロトタイプ変更として吸われ、そのパスが解決要求から静かに落ちる。
  var uniq = Object.create(null);
  targets.forEach(function(t) { uniq[t.raw] = true; });
  // 送れなかった(ハンドラ未登録の)場合は応答が来ないため、中立化もキュー登録も
  // 行わない。中立化したまま応答待ちで固まるのを防ぐ。
  if (!_mmdPostMessage(_MSG_RESOLVE_REFERENCES, { paths: Object.keys(uniq) })) { return; }
  targets.forEach(function(t) { t.el.classList.add('befold-link-pending'); });
  _mmdPendingRefBatches.push(targets);
}

// Swift からの解決結果(書かれたパス -> 解決済み絶対パス)を、最も古い未応答バッチへ
// 適用する。map に含まれるものだけリンク化し、含まれないものは通常テキストに戻す。
function _mmdApplyResolvedReferences(map) {
  var targets = _mmdPendingRefBatches.shift() || [];
  targets.forEach(function(t) {
    t.el.classList.remove('befold-link-pending');
    // 自己所有プロパティだけを見る。constructor / toString のような
    // Object.prototype の名前をパスとして書かれると、素の参照では
    // 未解決のパスが継承値で解決済みと誤判定される。
    var abs = (map && Object.prototype.hasOwnProperty.call(map, t.raw)) ? map[t.raw] : null;
    if (abs) {
      t.el.classList.add('befold-link');
      // コピー等の後続機能が使えるよう、解決済み絶対パスを DOM に残す。
      t.el.dataset.resolved = abs;
      // 表示テキストや文書側が付けた title は実際の遷移先と無関係になりうる
      // (生 HTML の span でリンク偽装が作れる)。解決先そのものを見せて上書きする。
      t.el.setAttribute('title', abs);
    } else {
      t.el.classList.add('befold-link-dead');
      if (t.el.tagName === 'A') { t.el.removeAttribute('href'); }
      t.el.removeAttribute('title');
    }
  });
}

// 再描画で #diagram-wrap の中身を捨てる直前に呼ぶ。未応答バッチの中身だけを空にし、
// 要素数 0 のバッチとして残す。キューの長さ(=未応答の要求数)を保つことで、
// 飛行中の応答が新しいバッチを誤って消費するのを防ぐ。
function _mmdInvalidatePendingRefs() {
  for (var i = 0; i < _mmdPendingRefBatches.length; i++) {
    _mmdPendingRefBatches[i] = [];
  }
}

export {
  isLocalPathHref,
  _annotatePathRefs,
  _walkTextNodes,
  _mmdResolveReferences,
  _mmdApplyResolvedReferences,
  _mmdInvalidatePendingRefs,
};
