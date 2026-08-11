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
// 既知の制約: シンタックスハイライトによってトークンが複数の <span> に
// 分割されている場合、その境界をまたぐパスは検出されない(シンプルな
// ヒューリスティックとして許容する)。
var _PATH_RE = /(?:(?<![/\w.])(?:\/?\.\.?\/[\w./-]+|[\w.-]+\/[\w./-]+)|(?:^|(?<=\s))\/[\w./-]+)(?:\.(?:swift|md|mmd|ts|tsx|js|jsx|py|rb|go|rs|java|kt|c|cpp|h|hpp|json|yaml|yml|toml|txt|html|css|sh))(?::\d+)*/g;

// パス検出の対象にするタグ(このタグに入った時点で配下は許可状態になる)。
// code はコードブロック(pre 配下)・インラインコードの両方を兼ねる。
var _PATH_ANNOTATE_TAGS = ['p', 'li', 'td', 'th', 'blockquote', 'dt', 'dd', 'code'];

function _annotatePathRefs() {
  var wrap = document.getElementById('diagram-wrap');
  if (wrap) { _walkTextNodes(wrap, false); }
}

// #diagram-wrap 配下を一度だけ再帰的に歩く。allowed は現在位置がパス検出の
// 対象コンテキスト内(_PATH_ANNOTATE_TAGS 配下)かどうかを表し、対象タグに
// 入った時点で true になり、非対象の子孫にもそのまま引き継がれる
// (例: <p> 内の <strong> のテキストも検出対象)。単一パスの走査のため、
// ネストしたタグ(li 内の li 等)を二重に処理する心配もない。
function _walkTextNodes(node, allowed) {
  if (node.nodeType === 3) { // TEXT_NODE
    if (!allowed) return;
    var text = node.textContent;
    _PATH_RE.lastIndex = 0;
    var match = _PATH_RE.exec(text);
    if (!match) return;
    var frag = document.createDocumentFragment();
    var lastIndex = 0;
    do {
      if (match.index > lastIndex) {
        frag.appendChild(document.createTextNode(text.slice(lastIndex, match.index)));
      }
      var span = document.createElement('span');
      span.className = 'befold-path-ref';
      span.dataset.path = match[0];
      span.textContent = match[0];
      frag.appendChild(span);
      lastIndex = _PATH_RE.lastIndex;
    } while ((match = _PATH_RE.exec(text)) !== null);
    if (lastIndex < text.length) {
      frag.appendChild(document.createTextNode(text.slice(lastIndex)));
    }
    node.parentNode.replaceChild(frag, node);
  } else if (node.nodeType === 1) {
    var tag = node.tagName.toLowerCase();
    // <a> 配下は既にリンクとして処理済み、svg/.mermaid は図中テキストの誤検出防止、
    // .befold-path-ref 配下は既存ガード(二重ラップ防止)。
    if (tag === 'a' || tag === 'svg' || node.classList.contains('mermaid') ||
        node.classList.contains('befold-path-ref')) {
      return;
    }
    var childAllowed;
    if (tag === 'pre') {
      // <pre> 直下のテキストは対象外(markdown-it の html:true により
      // <code> を伴わない生の <pre> がリスト項目内などに書かれた場合でも
      // 誤って対象化しないよう、祖先から引き継いだ allowed をリセットする)。
      // 内側の <code> は改めて自身で allowed = true にするため、
      // 従来の「pre code のみ対象」という範囲はそのまま維持される。
      childAllowed = false;
    } else {
      childAllowed = allowed || _PATH_ANNOTATE_TAGS.indexOf(tag) !== -1;
    }
    // スナップショットを取り順方向に走査(replaceChild で兄弟が変わるため)
    var children = Array.prototype.slice.call(node.childNodes);
    for (var j = 0; j < children.length; j++) {
      _walkTextNodes(children[j], childAllowed);
    }
  }
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
