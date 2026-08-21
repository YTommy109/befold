// 検索バー。クエリ・トグル・ヒット一覧・現在位置・開閉・段階読み込み中の
// すべてをコントローラのクロージャに閉じ、外部からは公開メソッド経由でのみ触れる。

import { wireBarControls } from './bar-controls.js';
import { claimBar, isBarOpen, registerBar, releaseBar } from './bar.js';
import { _MSG_FIND_OPTIONS_CHANGED, _mmdPostMessage } from './bridge.js';
import { isComposingKeyEvent } from './ime.js';
import {
  formatNavigationCount,
  moveCurrentHighlight,
  keptMatchIndex,
  nextMatchIndex,
  prevMatchIndex,
} from './navigation.js';

// 検索の 3 トグル。window._mmdInitialFindOptions（Swift が注入する側、すべて省略可）と
// 違い、コントローラ内部では 3 つとも常に確定している。
interface FindOptions {
  caseSensitive: boolean;
  wholeWord: boolean;
  useRegex: boolean;
}

// _createFindController が返す公開メソッド。他モジュール（truncation.ts /
// keyboard.js / render.js / init.js）はこの形だけを見る。
interface FindController {
  isOpen(): boolean;
  open(): void;
  close(): void;
  next(): void;
  prev(): void;
  refresh(resetToFirst?: boolean): void;
  applyHostSettings(): void;
  initControls(): void;
  setTruncated(value: boolean): void;
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

interface TextLocation {
  node: Text;
  localOffset: number;
}

// viewer.html に静的に置かれている <input>。getElementById は HTMLElement までしか
// 返さないため、instanceof で <input> であることを確かめてから返す。要素が消えた
// 場合は呼び出し側が value を触った時点ではなくここで TypeError になる（どちらも
// 復帰できない構成の壊れで、握り潰さない点は変えていない）。
function findInputElement(): HTMLInputElement {
  var el = document.getElementById('mmd-find-input');
  if (!(el instanceof HTMLInputElement)) {
    throw new TypeError('#mmd-find-input is missing');
  }
  return el;
}

// クエリと3トグル(caseSensitive / wholeWord / useRegex)から RegExp を組み立てる。
// クエリが空、または正規表現として不正な場合は null を返す(呼び出し側はエラー表示に切り替える)。
function buildFindRegExp(query: string, options: FindOptions): RegExp | null {
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

// 前回検索でハイライトした <mark> を復元する(次の検索前に必ず呼ぶ)。
// span 境界をまたぐマッチは <mark> の中に元の <span> 構造を保持したまま挿入して
// いるため、単純に textContent で潰すとシンタックスハイライトの構造が壊れる。
// mark を子ノードで置き換える(unwrap)ことで元の構造を保ったまま平文表示に戻す。
// normalize() は親ごとに1回だけ呼ぶ(同じ親に複数の <mark> がある場合の重複呼び出しを避ける)。
function clearMarks() {
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
function locate(
  textNodes: Text[],
  starts: number[],
  offset: number,
  isStart: boolean,
): TextLocation {
  for (var i = 0; i < textNodes.length; i++) {
    var start = starts[i]!;
    var length = textNodes[i]!.length;
    var fits = isStart ? offset < start + length : offset <= start + length;
    if (fits) {
      return { node: textNodes[i]!, localOffset: offset - start };
    }
  }
  var last = textNodes.length - 1;
  return { node: textNodes[last]!, localOffset: textNodes[last]!.length };
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

// 開閉状態は bar.ts が一元管理する（検索バーとジャンプバーは同時に開かない）。
function isFindBarOpen(): boolean {
  return isBarOpen('find');
}

function _createFindController(): FindController {
  var options: FindOptions = { caseSensitive: false, wholeWord: false, useRegex: false };
  var query = '';
  var matches: HTMLElement[] = [];
  var currentIndex = -1;
  // いま現在位置の印が付いている <mark>。付け替えのたびに全マッチを走査しないよう
  // 直前の要素だけを覚えておく。clearMarks で DOM ごと消えるため、
  // 列を作り直す経路（run / close）では併せて undefined に戻す。
  var currentHighlight: HTMLElement | undefined;
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
  // 位置を (textNode, localOffset) に逆引きして Range を組み、<mark> で置き換える。
  // ゼロ幅マッチ(例: 正規表現 "a*" の空文字一致)は無限ループを避けるため読み飛ばす。
  function matchScope(root: Node, textNodeList: Text[], regex: RegExp, found: HTMLElement[]): void {
    var starts: number[] = [];
    var text = '';
    textNodeList.forEach(function (node) {
      starts.push(text.length);
      // Text ノードの textContent は仕様上必ず文字列（null になるのは
      // Document / DocumentType などの場合のみ）。
      text += node.textContent!;
    });

    regex.lastIndex = 0;
    var ranges: { start: number; end: number }[] = [];
    var match: RegExpExecArray | null;
    while ((match = regex.exec(text)) !== null) {
      if (match[0].length === 0) {
        regex.lastIndex++;
        if (regex.lastIndex > text.length) break;
        continue;
      }
      ranges.push({ start: match.index, end: match.index + match[0].length });
    }
    if (ranges.length === 0) return;

    var scopeFound: HTMLElement[] = [];
    // Range 構築中に DOM を書き換えるとテキストノードがずれるため、末尾側から処理する。
    ranges.toReversed().forEach(function (range) {
      var start = locate(textNodeList, starts, range.start, true);
      var end = locate(textNodeList, starts, range.end, false);
      // extractContents() は境界をまたぐマッチの端で、部分的にしか含まれない祖先要素
      // (例: <span>foo</span> の "foo" 全体が対象でも境界が offset 0 なので「完全に
      // 含まれる」扱いにならない)を空のまま DOM に残す。参照はここで取っておき、
      // 抽出後に空になっていれば取り除く(そうしないと再検索のたびに空 <span> が
      // 増殖し、シンタックスハイライトの構造が壊れていく)。
      var startAncestor: Node | null = start.node.parentNode;
      var endAncestor: Node | null = end.node.parentNode;
      var domRange = document.createRange();
      domRange.setStart(start.node, start.localOffset);
      domRange.setEnd(end.node, end.localOffset);

      var mark = document.createElement('mark');
      mark.className = 'mmd-find-match';
      mark.append(domRange.extractContents());
      domRange.insertNode(mark);
      scopeFound.unshift(mark);

      pruneEmptyAncestors(startAncestor, root);
      pruneEmptyAncestors(endAncestor, root);
    });
    found.push.apply(found, scopeFound);
  }

  // #diagram-wrap 配下をスコープ(bridgeTags でつながった範囲)に分割し、スコープ
  // ごとにマッチさせる。document 順のまま found に積む。
  function walk(root: Node, regex: RegExp, found: HTMLElement[]): void {
    collectScopes(root).forEach(function (textNodeList) {
      matchScope(root, textNodeList, regex, found);
    });
  }

  // マッチなしを専用文言で表示すると文字幅の違いでバーが伸縮するため、
  // 常に「現在位置/件数」形式(マッチなし時は 0/0)のみを表示する。
  // 段階読み込み中(truncated)は表示済み DOM だけが検索対象であることを示すため
  // 「表示範囲内」ラベルを付与する。
  function updateCount(): void {
    var countEl = document.getElementById('mmd-find-count')!;
    var input = findInputElement();
    if (query.length === 0 || input.classList.contains('mmd-find-error')) {
      countEl.textContent = '';
    } else {
      var strings: ViewerFindStrings = window._mmdFindStrings || {};
      countEl.textContent = formatNavigationCount(
        currentIndex,
        matches.length,
        truncated,
        strings.withinDisplayedRange || 'Displayed range',
      );
    }
  }

  function highlightCurrent(): void {
    var current = matches[currentIndex];
    // 印の付け替えとスクロールは navigation.ts に集約する（ジャンプバーと同じ挙動）。
    // 直前の要素だけを渡すので、マッチが何万件あっても走査は起きない。
    moveCurrentHighlight(
      currentHighlight ? [currentHighlight] : [],
      current ? [current] : [],
      'mmd-find-match-current',
      current,
    );
    currentHighlight = current;
  }

  // 現在位置を移し、ハイライトと件数表示を揃える(next/prev/refresh 共通)。
  function moveTo(index: number): void {
    currentIndex = index;
    highlightCurrent();
    updateCount();
  }

  // 入力・トグル変更のたびに呼ばれる: 現在のハイライトをクリアして再検索する。
  // suppressAutoHighlight を true にすると、1件目への自動ハイライト・スクロールを行わない
  // (呼び出し元が位置確定後に自分でハイライトする場合に使う。refresh 参照)。
  function run(suppressAutoHighlight?: boolean): void {
    var input = findInputElement();
    query = input.value;
    clearMarks();
    matches = [];
    currentIndex = -1;
    currentHighlight = undefined;

    var regex = buildFindRegExp(query, options);
    input.classList.toggle('mmd-find-error', query.length > 0 && regex === null);

    if (regex) {
      walk(document.getElementById('diagram-wrap')!, regex, matches);
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
  function refresh(resetToFirst?: boolean): void {
    var previousIndex = resetToFirst ? 0 : currentIndex;
    run(true);
    if (matches.length > 0) {
      moveTo(keptMatchIndex(previousIndex, matches.length));
    }
  }

  function next(): void {
    if (matches.length === 0) return;
    moveTo(nextMatchIndex(currentIndex, matches.length));
  }

  function prev(): void {
    if (matches.length === 0) return;
    moveTo(prevMatchIndex(currentIndex, matches.length));
  }

  // トグルボタン共通のハンドラ: 状態を反転し、見た目を更新し、Swift へ永続化を依頼して再検索する。
  function toggleOption(optionName: keyof FindOptions, buttonId: string): void {
    options[optionName] = !options[optionName];
    document.getElementById(buttonId)!.classList.toggle('active', options[optionName]);
    _mmdPostMessage(_MSG_FIND_OPTIONS_CHANGED, {
      caseSensitive: options.caseSensitive,
      wholeWord: options.wholeWord,
      useRegex: options.useRegex,
    });
    run();
  }

  // ロード時に保存済みトグル状態(window._mmdInitialFindOptions、Swift から注入)と
  // ローカライズ済み文字列(window._mmdFindStrings、Swift から注入)を反映する。
  function applyHostSettings(): void {
    var opts: ViewerFindOptions = window._mmdInitialFindOptions || {};
    options.caseSensitive = !!opts.caseSensitive;
    options.wholeWord = !!opts.wholeWord;
    options.useRegex = !!opts.useRegex;
    document.getElementById('mmd-find-case')!.classList.toggle('active', options.caseSensitive);
    document.getElementById('mmd-find-word')!.classList.toggle('active', options.wholeWord);
    document.getElementById('mmd-find-regex')!.classList.toggle('active', options.useRegex);

    var strings: ViewerFindStrings = window._mmdFindStrings || {};
    var input = findInputElement();
    if (strings.placeholder) {
      input.placeholder = strings.placeholder;
    }
    if (strings.previous) {
      document.getElementById('mmd-find-prev')!.title = strings.previous;
    }
    if (strings.next) {
      document.getElementById('mmd-find-next')!.title = strings.next;
    }
    if (strings.matchCase) {
      document.getElementById('mmd-find-case')!.title = strings.matchCase;
    }
    if (strings.matchWholeWord) {
      document.getElementById('mmd-find-word')!.title = strings.matchWholeWord;
    }
    if (strings.useRegularExpression) {
      document.getElementById('mmd-find-regex')!.title = strings.useRegularExpression;
    }
    if (strings.close) {
      document.getElementById('mmd-find-close')!.title = strings.close;
    }
  }

  function initControls(): void {
    document.getElementById('mmd-find-input')!.addEventListener('input', function () {
      run();
    });
    document.getElementById('mmd-find-input')!.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') {
        // 変換確定の Enter では検索を進めない（判定は ime.ts に集約）。
        if (isComposingKeyEvent(e)) {
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
    wireBarControls({
      prevId: 'mmd-find-prev',
      nextId: 'mmd-find-next',
      closeId: 'mmd-find-close',
      onPrev: prev,
      onNext: next,
      onClose: close,
    });
    document.getElementById('mmd-find-case')!.addEventListener('click', function () {
      toggleOption('caseSensitive', 'mmd-find-case');
    });
    document.getElementById('mmd-find-word')!.addEventListener('click', function () {
      toggleOption('wholeWord', 'mmd-find-word');
    });
    document.getElementById('mmd-find-regex')!.addEventListener('click', function () {
      toggleOption('useRegex', 'mmd-find-regex');
    });
  }

  function open(): void {
    claimBar('find');
    document.getElementById('mmd-find-panel')!.style.display = 'flex';
    var input = findInputElement();
    input.value = query;
    input.focus();
    input.select();
    // 段階読み込み中(truncated)でも未読み込み部分は検索対象にせず、
    // 表示済み DOM のみを検索する(件数表示は updateCount が「表示範囲内」を付与する)。
    run();
  }

  function close(): void {
    releaseBar('find');
    document.getElementById('mmd-find-panel')!.style.display = 'none';
    clearMarks();
    matches = [];
    currentIndex = -1;
    currentHighlight = undefined;
  }

  // 段階読み込み状態の変化を件数表示(「表示範囲内」ラベル)へ反映する。
  // バナー自体の表示切替は _mmdSetTruncated が担う。
  function setTruncated(value: boolean): void {
    truncated = value;
    // 検索バーが開いていれば「表示範囲内」ラベルの表示/非表示を即座に反映する。
    // (通常は appendChunk 後の _mmdFindRefreshAfterRender が再検索するが、
    // それより先に評価されるため、ここでも件数表示だけ更新しておく)
    if (isFindBarOpen()) {
      updateCount();
    }
  }

  return {
    isOpen: isFindBarOpen,
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

// Escape や、別のバーを開いたときの自動クローズはレジストリ経由で届く。
registerBar('find', {
  close: function (): void {
    _mmdFind.close();
  },
});

// 以下は Swift(evaluateJavaScript)から名前で呼ばれる入口。ViewerBridge の
// 各 script 定数と一対一で対応するため、コントローラへの委譲だけを行う。
function _mmdInitFind(): void {
  _mmdFind.applyHostSettings();
}

function _mmdOpenFind(): void {
  _mmdFind.open();
}

function _mmdCloseFind(): void {
  _mmdFind.close();
}

function _mmdFindRefresh(resetToFirst?: boolean): void {
  _mmdFind.refresh(resetToFirst);
}

// ⌘G / ⌘Shift+G から呼ばれる。検索バーが閉じている間は何もしない
// (フォーカス位置に関わらずグローバルショートカットとして配線されるため、
// 呼び出し側では開閉判定をせずここで一元的にガードする)。
function _mmdFindNextIfOpen(): void {
  if (!_mmdFind.isOpen()) return;
  _mmdFind.next();
}

function _mmdFindPrevIfOpen(): void {
  if (!_mmdFind.isOpen()) return;
  _mmdFind.prev();
}

export {
  buildFindRegExp,
  _mmdFind,
  _mmdInitFind,
  _mmdOpenFind,
  _mmdCloseFind,
  _mmdFindRefresh,
  _mmdFindNextIfOpen,
  _mmdFindPrevIfOpen,
};
