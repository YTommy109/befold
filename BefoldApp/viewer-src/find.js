// 検索バー。クエリ・トグル・ヒット一覧・現在位置・開閉・段階読み込み中の
// すべてをコントローラのクロージャに閉じ、外部からは公開メソッド経由でのみ触れる。

import { _MSG_FIND_OPTIONS_CHANGED, _mmdPostMessage } from './bridge.js';

// クエリと3トグル(caseSensitive / wholeWord / useRegex)から RegExp を組み立てる。
// クエリが空、または正規表現として不正な場合は null を返す(呼び出し側はエラー表示に切り替える)。
function buildFindRegExp(query, options) {
  if (!query) {
    return null;
  }
  var source = options.useRegex ? query : query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
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

// 検索ヒット間の移動先インデックス。件数 0 のときはどれも -1(選択なし)を返す。
// 末尾の次は先頭、先頭の前は末尾へ循環する。

function nextMatchIndex(currentIndex, count) {
  if (count <= 0) {
    return -1;
  }
  return (currentIndex + 1) % count;
}

function prevMatchIndex(currentIndex, count) {
  if (count <= 0) {
    return -1;
  }
  return (currentIndex - 1 + count) % count;
}

// 再検索(_mmdFindRefresh)で維持する現在位置。再検索でヒット数が減っても
// 範囲外を指さないようクランプする。負値(未選択)は先頭に寄せる。
function keptMatchIndex(previousIndex, count) {
  if (count <= 0) {
    return -1;
  }
  return Math.min(Math.max(previousIndex, 0), count - 1);
}

function _createFindController() {
  var options = { caseSensitive: false, wholeWord: false, useRegex: false };
  var query = '';
  var matches = [];
  var currentIndex = -1;
  var isOpenFlag = false;
  // 段階読み込み中(まだ全チャンクを読み終えていない)かどうか。setTruncated が更新する。
  var truncated = false;

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

  // 前回検索でハイライトした <mark> を復元する(次の検索前に必ず呼ぶ)。
  // span 境界をまたぐマッチは <mark> の中に元の <span> 構造を保持したまま挿入して
  // いるため、単純に textContent で潰すとシンタックスハイライトの構造が壊れる。
  // mark を子ノードで置き換える(unwrap)ことで元の構造を保ったまま平文表示に戻す。
  // normalize() は親ごとに1回だけ呼ぶ(同じ親に複数の <mark> がある場合の重複呼び出しを避ける)。
  function clearMarks() {
    var marks = document.querySelectorAll('#diagram-wrap mark.mmd-find-match');
    var parents = new Set();
    marks.forEach(function (mark) {
      var parent = mark.parentNode;
      if (!parent) return;
      while (mark.firstChild) {
        parent.insertBefore(mark.firstChild, mark);
      }
      parent.removeChild(mark);
      parents.add(parent);
    });
    parents.forEach(function (parent) {
      parent.normalize();
    });
  }

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

  function isBridgeable(node) {
    return node.nodeType === 1 && bridgeTags.indexOf(node.tagName.toUpperCase()) !== -1;
  }

  // #diagram-wrap 配下(skipTags 除く)を再帰し、bridgeTags で連結できる範囲だけを
  // 1つの「スコープ」(テキストノードの配列)としてまとめる。見出し・段落・リスト
  // 項目・テーブル行/セルなど bridgeTags 以外の要素に出会うたびにスコープを区切る
  // ことで、シンタックスハイライトの <span> 境界はまたぎつつ、行番号付きコード
  // ブロックの <tr>/<td> のような構造上の境界はまたがないようにする(またぐと
  // Range.extractContents() がテーブル構造を破壊してレイアウトが崩れる)。
  // スコープはすべて document 順で返す。
  function collectScopes(root) {
    var scopes = [];
    var current = [];
    function flush() {
      if (current.length > 0) {
        scopes.push(current);
        current = [];
      }
    }
    function recurse(node) {
      var children = node.childNodes;
      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (child.nodeType === 3) {
          current.push(child);
        } else if (child.nodeType === 1 && skipTags.indexOf(child.tagName.toUpperCase()) === -1) {
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

  // 連結文字列上のオフセットを (テキストノード, ノード内オフセット) に逆引きする。
  // textNodes[i] は連結文字列上で [starts[i], starts[i] + textNodes[i].length) を占める。
  //
  // ノードの継ぎ目ちょうどのオフセット(前ノードの終端 === 次ノードの先頭)は
  // DOM 上は同じ位置を指すが、Range の「祖先を完全に含むか」の判定はどちらの
  // ノードを境界に使うかで変わる。開始側は次ノードの先頭(offset 0)、終了側は
  // 前ノードの終端を使わないと、実際にはマッチしていない隣接 <span> まで
  // 「部分的に含む」扱いになり、意図せず分割・複製されてしまう
  // (isStart=true: 継ぎ目では後方のノードを優先。isStart=false: 前方のノードを優先)。
  function locate(textNodes, starts, offset, isStart) {
    for (var i = 0; i < textNodes.length; i++) {
      var start = starts[i];
      var length = textNodes[i].length;
      var fits = isStart ? offset < start + length : offset <= start + length;
      if (fits) {
        return { node: textNodes[i], localOffset: offset - start };
      }
    }
    var last = textNodes.length - 1;
    return { node: textNodes[last], localOffset: textNodes[last].length };
  }

  // 1スコープ(bridgeTags でつながった範囲)のテキストを連結してマッチさせ、マッチ
  // 位置を (textNode, localOffset) に逆引きして Range を組み、<mark> で置き換える。
  // ゼロ幅マッチ(例: 正規表現 "a*" の空文字一致)は無限ループを避けるため読み飛ばす。
  function matchScope(root, textNodeList, regex, found) {
    var starts = [];
    var text = '';
    textNodeList.forEach(function (node) {
      starts.push(text.length);
      text += node.textContent;
    });

    regex.lastIndex = 0;
    var ranges = [];
    var match;
    while ((match = regex.exec(text)) !== null) {
      if (match[0].length === 0) {
        regex.lastIndex++;
        if (regex.lastIndex > text.length) break;
        continue;
      }
      ranges.push({ start: match.index, end: match.index + match[0].length });
    }
    if (ranges.length === 0) return;

    var scopeFound = [];
    // Range 構築中に DOM を書き換えるとテキストノードがずれるため、末尾側から処理する。
    ranges.toReversed().forEach(function (range) {
      var start = locate(textNodeList, starts, range.start, true);
      var end = locate(textNodeList, starts, range.end, false);
      // extractContents() は境界をまたぐマッチの端で、部分的にしか含まれない祖先要素
      // (例: <span>foo</span> の "foo" 全体が対象でも境界が offset 0 なので「完全に
      // 含まれる」扱いにならない)を空のまま DOM に残す。参照はここで取っておき、
      // 抽出後に空になっていれば取り除く(そうしないと再検索のたびに空 <span> が
      // 増殖し、シンタックスハイライトの構造が壊れていく)。
      var startAncestor = start.node.parentNode;
      var endAncestor = end.node.parentNode;
      var domRange = document.createRange();
      domRange.setStart(start.node, start.localOffset);
      domRange.setEnd(end.node, end.localOffset);

      var mark = document.createElement('mark');
      mark.className = 'mmd-find-match';
      mark.appendChild(domRange.extractContents());
      domRange.insertNode(mark);
      scopeFound.unshift(mark);

      pruneEmptyAncestors(startAncestor, root);
      pruneEmptyAncestors(endAncestor, root);
    });
    found.push.apply(found, scopeFound);
  }

  // #diagram-wrap 配下をスコープ(bridgeTags でつながった範囲)に分割し、スコープ
  // ごとにマッチさせる。document 順のまま found に積む。
  function walk(root, regex, found) {
    collectScopes(root).forEach(function (textNodeList) {
      matchScope(root, textNodeList, regex, found);
    });
  }

  // node から祖先方向へ、内容が空になった要素を取り除く(root には触れない)。
  // extractContents() は境界の Text ノードを削除せず長さ0のまま残すため、
  // hasChildNodes() ではなく textContent で空判定する。
  function pruneEmptyAncestors(node, root) {
    while (node && node !== root && node.nodeType === 1 && node.textContent === '') {
      var parent = node.parentNode;
      if (!parent) break;
      parent.removeChild(node);
      node = parent;
    }
  }

  // マッチなしを専用文言で表示すると文字幅の違いでバーが伸縮するため、
  // 常に「現在位置/件数」形式(マッチなし時は 0/0)のみを表示する。
  // 段階読み込み中(truncated)は表示済み DOM だけが検索対象であることを示すため
  // 「表示範囲内」ラベルを付与する。
  function updateCount() {
    var countEl = document.getElementById('mmd-find-count');
    var input = document.getElementById('mmd-find-input');
    if (query.length === 0 || input.classList.contains('mmd-find-error')) {
      countEl.textContent = '';
    } else {
      var current = matches.length === 0 ? 0 : currentIndex + 1;
      var text = current + '/' + matches.length;
      if (truncated) {
        var strings = window._mmdFindStrings || {};
        text += ' (' + (strings.withinDisplayedRange || 'Displayed range') + ')';
      }
      countEl.textContent = text;
    }
  }

  function highlightCurrent() {
    matches.forEach(function (mark) {
      mark.classList.remove('mmd-find-match-current');
    });
    var current = matches[currentIndex];
    if (!current) return;
    current.classList.add('mmd-find-match-current');
    current.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }

  // 現在位置を移し、ハイライトと件数表示を揃える(next/prev/refresh 共通)。
  function moveTo(index) {
    currentIndex = index;
    highlightCurrent();
    updateCount();
  }

  // 入力・トグル変更のたびに呼ばれる: 現在のハイライトをクリアして再検索する。
  // suppressAutoHighlight を true にすると、1件目への自動ハイライト・スクロールを行わない
  // (呼び出し元が位置確定後に自分でハイライトする場合に使う。refresh 参照)。
  function run(suppressAutoHighlight) {
    var input = document.getElementById('mmd-find-input');
    query = input.value;
    clearMarks();
    matches = [];
    currentIndex = -1;

    var regex = buildFindRegExp(query, options);
    input.classList.toggle('mmd-find-error', query.length > 0 && regex === null);

    if (regex) {
      walk(document.getElementById('diagram-wrap'), regex, matches);
    }

    if (matches.length > 0) {
      currentIndex = 0;
      if (!suppressAutoHighlight) {
        highlightCurrent();
      }
    }
    updateCount();
  }

  // render() / _renderSource() の末尾から呼ばれる: バーが開いていれば
  // 同じクエリ・トグルのまま新しい DOM に対して再検索する。
  // resetToFirst が真の場合は1件目に位置をリセットする(モード切替時: レンダリング結果と
  // ソースコードとで DOM 構造に連続性がないため、位置維持に意味がない)。
  // 省略時は可能な限り現在位置を維持する(ライブリロード追従)。
  // run には suppressAutoHighlight=true を渡し、1件目への自動スクロールを抑止した上で、
  // 位置確定後にここで1回だけ highlightCurrent() を呼ぶ(二重スクロール防止)。
  function refresh(resetToFirst) {
    var previousIndex = resetToFirst ? 0 : currentIndex;
    run(true);
    if (matches.length > 0) {
      moveTo(keptMatchIndex(previousIndex, matches.length));
    }
  }

  function next() {
    if (matches.length === 0) return;
    moveTo(nextMatchIndex(currentIndex, matches.length));
  }

  function prev() {
    if (matches.length === 0) return;
    moveTo(prevMatchIndex(currentIndex, matches.length));
  }

  // トグルボタン共通のハンドラ: 状態を反転し、見た目を更新し、Swift へ永続化を依頼して再検索する。
  function toggleOption(optionName, buttonId) {
    options[optionName] = !options[optionName];
    document.getElementById(buttonId).classList.toggle('active', options[optionName]);
    _mmdPostMessage(_MSG_FIND_OPTIONS_CHANGED, {
      caseSensitive: options.caseSensitive,
      wholeWord: options.wholeWord,
      useRegex: options.useRegex,
    });
    run();
  }

  // ロード時に保存済みトグル状態(window._mmdInitialFindOptions、Swift から注入)と
  // ローカライズ済み文字列(window._mmdFindStrings、Swift から注入)を反映する。
  function applyHostSettings() {
    var opts = window._mmdInitialFindOptions || {};
    options.caseSensitive = !!opts.caseSensitive;
    options.wholeWord = !!opts.wholeWord;
    options.useRegex = !!opts.useRegex;
    document.getElementById('mmd-find-case').classList.toggle('active', options.caseSensitive);
    document.getElementById('mmd-find-word').classList.toggle('active', options.wholeWord);
    document.getElementById('mmd-find-regex').classList.toggle('active', options.useRegex);

    var strings = window._mmdFindStrings || {};
    var input = document.getElementById('mmd-find-input');
    if (strings.placeholder) {
      input.placeholder = strings.placeholder;
    }
    if (strings.previous) {
      document.getElementById('mmd-find-prev').title = strings.previous;
    }
    if (strings.next) {
      document.getElementById('mmd-find-next').title = strings.next;
    }
    if (strings.matchCase) {
      document.getElementById('mmd-find-case').title = strings.matchCase;
    }
    if (strings.matchWholeWord) {
      document.getElementById('mmd-find-word').title = strings.matchWholeWord;
    }
    if (strings.useRegularExpression) {
      document.getElementById('mmd-find-regex').title = strings.useRegularExpression;
    }
    if (strings.close) {
      document.getElementById('mmd-find-close').title = strings.close;
    }
  }

  function initControls() {
    document.getElementById('mmd-find-input').addEventListener('input', function () {
      run();
    });
    document.getElementById('mmd-find-input').addEventListener('keydown', function (e) {
      if (e.key === 'Enter') {
        // Safari/WKWebView は compositionend → keydown の順で発火するため、
        // 変換確定の Enter では isComposing が既に false になっている。
        // ただし keyCode は 229 のまま残るため、これも合わせて判定する。
        if (e.isComposing || e.keyCode === 229) {
          return;
        }
        e.preventDefault();
        if (e.shiftKey) {
          prev();
        } else {
          next();
        }
      }
      // Escape はここでは処理しない: document の keydown ハンドラがバブリングで捕捉し、
      // isOpen() 時に preventDefault + close() を行う(同じ挙動になる)。
    });
    document.getElementById('mmd-find-next').addEventListener('click', next);
    document.getElementById('mmd-find-prev').addEventListener('click', prev);
    document.getElementById('mmd-find-close').addEventListener('click', close);
    document.getElementById('mmd-find-case').addEventListener('click', function () {
      toggleOption('caseSensitive', 'mmd-find-case');
    });
    document.getElementById('mmd-find-word').addEventListener('click', function () {
      toggleOption('wholeWord', 'mmd-find-word');
    });
    document.getElementById('mmd-find-regex').addEventListener('click', function () {
      toggleOption('useRegex', 'mmd-find-regex');
    });
  }

  function open() {
    isOpenFlag = true;
    document.getElementById('mmd-find-bar').style.display = 'flex';
    var input = document.getElementById('mmd-find-input');
    input.value = query;
    input.focus();
    input.select();
    // 段階読み込み中(truncated)でも未読み込み部分は検索対象にせず、
    // 表示済み DOM のみを検索する(件数表示は updateCount が「表示範囲内」を付与する)。
    run();
  }

  function close() {
    isOpenFlag = false;
    document.getElementById('mmd-find-bar').style.display = 'none';
    clearMarks();
    matches = [];
    currentIndex = -1;
  }

  // 段階読み込み状態の変化を件数表示(「表示範囲内」ラベル)へ反映する。
  // バナー自体の表示切替は _mmdSetTruncated が担う。
  function setTruncated(value) {
    truncated = value;
    // 検索バーが開いていれば「表示範囲内」ラベルの表示/非表示を即座に反映する。
    // (通常は appendChunk 後の _mmdFindRefreshAfterRender が再検索するが、
    // それより先に評価されるため、ここでも件数表示だけ更新しておく)
    if (isOpenFlag) {
      updateCount();
    }
  }

  return {
    isOpen: function () {
      return isOpenFlag;
    },
    open: open,
    close: close,
    next: next,
    prev: prev,
    refresh: refresh,
    applyHostSettings: applyHostSettings,
    initControls: initControls,
    setTruncated: setTruncated,
  };
}

var _mmdFind = _createFindController();

// 以下は Swift(evaluateJavaScript)から名前で呼ばれる入口。ViewerBridge の
// 各 script 定数と一対一で対応するため、コントローラへの委譲だけを行う。
function _mmdInitFind() {
  _mmdFind.applyHostSettings();
}

function _mmdOpenFind() {
  _mmdFind.open();
}

function _mmdCloseFind() {
  _mmdFind.close();
}

function _mmdFindRefresh(resetToFirst) {
  _mmdFind.refresh(resetToFirst);
}

// ⌘G / ⌘Shift+G から呼ばれる。検索バーが閉じている間は何もしない
// (フォーカス位置に関わらずグローバルショートカットとして配線されるため、
// 呼び出し側では開閉判定をせずここで一元的にガードする)。
function _mmdFindNextIfOpen() {
  if (!_mmdFind.isOpen()) return;
  _mmdFind.next();
}

function _mmdFindPrevIfOpen() {
  if (!_mmdFind.isOpen()) return;
  _mmdFind.prev();
}

export {
  buildFindRegExp,
  nextMatchIndex,
  prevMatchIndex,
  keptMatchIndex,
  _mmdFind,
  _mmdInitFind,
  _mmdOpenFind,
  _mmdCloseFind,
  _mmdFindRefresh,
  _mmdFindNextIfOpen,
  _mmdFindPrevIfOpen,
};
