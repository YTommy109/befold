// 文書内ジャンプ。文書順に並んだ目印（見出し・変更ブロック・関数定義など）の列を
// 前後に移動する。検索バーと同じ「列 + 現在位置 + n/N 表示」の形をとるが、
// 列の作り方だけが対象ごとに違うため、列挙は JumpProvider に委ねてここには持たない。
//
// 位置の算術と件数ラベルは navigation.ts、バーの排他は bar.ts と共有する。

import { claimBar, isBarOpen, registerBar, releaseBar } from './bar.js';
import {
  formatNavigationCount,
  keptMatchIndex,
  nextMatchIndex,
  prevMatchIndex,
} from './navigation.js';

// 1 つの目印。anchor はスクロール先、highlight は目立たせる要素。
// 差分の左右分割のように 1 つの目印が複数の要素で表される場合があるため、
// highlight は配列で持つ（anchor は highlight の代表とは限らない）。
interface JumpTarget {
  anchor: HTMLElement;
  highlight: HTMLElement[];
}

// 目印の列挙だけを担う差し替え点。root（#diagram-wrap）配下を文書順に走査する。
interface JumpProvider {
  id: string;
  collect(root: HTMLElement): JumpTarget[];
  // 列挙の条件そのものが「何も選ばれていない」状態か。真なら 0 件の原因は
  // 文書ではなく利用者の選択なので、件数表示の「表示範囲内」ラベルを出さない。
  // 省略時は常に false（選択の概念を持たない対象）。
  isSelectionEmpty?(): boolean;
  // 段階読み込みの影響を受けない対象か。真なら「表示範囲内」ラベルを出さない。
  // 差分表示は setDiff で渡った全文から表を組み、appendChunk が追記を
  // スキップする（render.ts の 'diff' 分岐）ため、本文が段階読み込み中でも
  // 変更ブロックは常に全数が DOM 上にある。ここを見ずに truncated だけで
  // ラベルを出すと事実と食い違う。
  ignoresTruncation?: boolean;
  // この対象だけが使うバー内オプションの要素 id（見出しレベルのトグルなど）。
  // 何を出すかはプロバイダ側の関心なので、コントローラは
  // 「active な対象のものだけ表示する」ことしか知らない。
  optionsElementId?: string;
}

interface JumpController {
  isOpen(): boolean;
  open(kind: string): void;
  close(): void;
  next(): void;
  prev(): void;
  // 描画・チャンク追記のあとに列を作り直す。位置は可能な限り維持する。
  // resetToFirst が真なら先頭へ戻す（表示モード切替時）。
  refresh(resetToFirst?: boolean): void;
  // 列挙の条件が変わったときに列を作り直す（描画中は着地時の refresh に任せる）。
  rebuild(): void;
  // 描画の開始時に列を捨てる。着地までの間、前の文書の n/N と
  // ハイライトが残らないようにする。
  invalidate(): void;
  setTruncated(value: boolean): void;
  register(provider: JumpProvider): void;
}

var CURRENT_CLASS = 'mmd-jump-current';
// 目印の候補であることを示すクラス。バーを開いている間だけ付き、
// 次にどこへ飛べるかをユーザーへ見せる（TASK-485.2）。
var TARGET_CLASS = 'mmd-jump-target';

// 現在位置の印だけを取り除く（次の位置へ付け替えるときに使う）。
// 候補の印は列が変わらない限り残す。
function clearCurrent(targets: JumpTarget[]): void {
  targets.forEach(function (target) {
    target.highlight.forEach(function (element) {
      element.classList.remove(CURRENT_CLASS);
    });
  });
}

// 目印の列から、候補と現在位置の印を両方取り除く。
//
// **列を捨てる経路はすべてこの関数を通す。** 列が入れ替わるのは open だけでなく
// refresh（描画・チャンク追記・レベル変更）でも起きるため、片方の経路だけで
// 外す形にすると古い候補の下線が残る。
function clearHighlight(targets: JumpTarget[]): void {
  clearCurrent(targets);
  targets.forEach(function (target) {
    target.highlight.forEach(function (element) {
      element.classList.remove(TARGET_CLASS);
    });
  });
}

// 目印の候補すべてに印を付ける。
function markTargets(targets: JumpTarget[]): void {
  targets.forEach(function (target) {
    target.highlight.forEach(function (element) {
      element.classList.add(TARGET_CLASS);
    });
  });
}

// 開閉状態は bar.ts が一元管理する（検索バーとジャンプバーは同時に開かない）。
function isJumpBarOpen(): boolean {
  return isBarOpen('jump');
}

function _createJumpController(): JumpController {
  var providers: Record<string, JumpProvider> = {};
  var activeKind = '';
  var targets: JumpTarget[] = [];
  var currentIndex = -1;
  // 段階読み込み中（まだ全チャンクを読み終えていない）かどうか。
  // 真のときは表示済み DOM の分しか数えられないことを件数表示で示す。
  var truncated = false;
  // 描画中（invalidate から着地の refresh までの間）。rebuild の抑止に使う。
  // 立てるのは invalidate、下ろすのは refresh の各 1 箇所だけ。
  var isRendering = false;

  function register(provider: JumpProvider): void {
    providers[provider.id] = provider;
  }

  function updateCount(): void {
    var countEl = document.getElementById('mmd-jump-count');
    if (!countEl) return;
    var strings: ViewerJumpStrings = window._mmdJumpStrings || {};
    // 「表示範囲内」は"まだ読んでいない範囲は数えられていない"という意味なので、
    // 目印の種類そのものが選ばれていないとき（列挙の条件で 0 件）は出さない。
    // 段階読み込み中でも 0 件の原因は読み込み範囲ではないため、事実と食い違う。
    var showsTruncatedLabel = truncated && !isFilteredEmpty() && !ignoresTruncation();
    countEl.textContent = formatNavigationCount(
      currentIndex,
      targets.length,
      showsTruncatedLabel,
      strings.withinDisplayedRange || 'Displayed range',
    );
  }

  // 現在位置を目立たせる。scroll は next/prev/open のときだけ真にする。
  // 再構築（refresh）で毎回スクロールすると、段階読み込み中にチャンクが
  // 届くたび読んでいる位置を奪ってしまう（appendChunk 経路には
  // スクロール復元が無い）。
  function highlightCurrent(scroll: boolean): void {
    clearCurrent(targets);
    var current = targets[currentIndex];
    if (!current) return;
    current.highlight.forEach(function (element) {
      element.classList.add(CURRENT_CLASS);
    });
    if (scroll) {
      current.anchor.scrollIntoView({ block: 'center', behavior: 'smooth' });
    }
  }

  function moveTo(index: number, scroll: boolean): void {
    currentIndex = index;
    highlightCurrent(scroll);
    updateCount();
  }

  // 目印の列を作り直す。列挙はプロバイダに委ねる。
  function collectTargets(): JumpTarget[] {
    var provider = providers[activeKind];
    var root = document.getElementById('diagram-wrap');
    if (!provider || !root) {
      return [];
    }
    return provider.collect(root);
  }

  // いま有効なプロバイダが「何も選ばれていない」状態か。
  function isFilteredEmpty(): boolean {
    var provider = providers[activeKind];
    return provider?.isSelectionEmpty?.() === true;
  }

  // いま有効なプロバイダが段階読み込みの影響を受けない対象か。
  function ignoresTruncation(): boolean {
    return providers[activeKind]?.ignoresTruncation === true;
  }

  // バー内のオプション要素を、いま有効な対象のものだけ表示する。
  // 登録済みのプロバイダを全部走査するのは、対象を切り替えたときに
  // 前の対象のオプションが残らないようにするため（open のたびに全消し→1 つ表示）。
  function updateOptionsVisibility(): void {
    Object.keys(providers).forEach(function (id) {
      var elementId = providers[id]?.optionsElementId;
      if (!elementId) return;
      var element = document.getElementById(elementId);
      if (!element) return;
      element.style.display = id === activeKind ? 'flex' : 'none';
    });
  }

  function run(scroll: boolean): void {
    clearHighlight(targets);
    targets = collectTargets();
    markTargets(targets);
    currentIndex = targets.length > 0 ? 0 : -1;
    highlightCurrent(scroll);
    updateCount();
  }

  function open(kind: string): void {
    activeKind = kind;
    claimBar('jump');
    var bar = document.getElementById('mmd-jump-bar');
    if (bar) {
      bar.style.display = 'flex';
    }
    updateOptionsVisibility();
    run(true);
  }

  function close(): void {
    releaseBar('jump');
    var bar = document.getElementById('mmd-jump-bar');
    if (bar) {
      bar.style.display = 'none';
    }
    clearHighlight(targets);
    targets = [];
    currentIndex = -1;
  }

  function next(): void {
    if (targets.length === 0) return;
    moveTo(nextMatchIndex(currentIndex, targets.length), true);
  }

  function prev(): void {
    if (targets.length === 0) return;
    moveTo(prevMatchIndex(currentIndex, targets.length), true);
  }

  function refresh(resetToFirst?: boolean): void {
    // 描画の着地。バーの開閉に関わらず必ずここへ来るため（render.ts の
    // _mmdFindRefreshAfterRender は無条件に呼ぶ）、描画中フラグを下ろすのは
    // ここ 1 箇所でよい。立てるのは invalidate の 1 箇所。
    isRendering = false;
    // 閉じている間は列を作らない。作ると候補の印（下線）が付いてしまう。
    if (!isJumpBarOpen()) {
      return;
    }
    var previousIndex = resetToFirst ? 0 : currentIndex;
    clearHighlight(targets);
    targets = collectTargets();
    markTargets(targets);
    currentIndex = -1;
    if (targets.length > 0) {
      moveTo(keptMatchIndex(previousIndex, targets.length), false);
    } else {
      updateCount();
    }
  }

  // 列挙の条件が変わったので列を作り直す（見出しレベルのトグルなど）。
  // 列の同一性が変わるため現在位置は先頭へ戻す。
  //
  // 描画中は何もしない。render() は invalidate から着地の refresh までの間
  // DOM を差し替えている最中で、その途中の DOM から作った currentIndex を
  // 着地時の refresh が位置維持の入力に使ってしまう（表示は最終的に正しくなるが
  // 位置維持の意図だけが静かに壊れる）。着地時の refresh が新しい条件で作り直すので
  // ここでスキップしても取りこぼさない。判定は DOM の中身ではなく内部状態で行う。
  function rebuild(): void {
    if (!isJumpBarOpen() || isRendering) {
      return;
    }
    refresh(true);
  }

  function invalidate(): void {
    // DOM は既に差し替わっている場合があるため、クラスの取り外しは行わず
    // 列だけを捨てる（残ったクラスは古い DOM ごと消える）。
    //
    // currentIndex はここでは捨てない。着地時の refresh が「可能な限り位置を
    // 維持する」ために前の位置を要るため（捨てると再描画のたびに先頭へ戻る）。
    // 列が空の間、件数表示は 0/0 になる（formatNavigationCount は件数 0 のとき
    // 現在位置を 0 として組み立てる）ので、表示上も前の位置は見えない。
    isRendering = true;
    targets = [];
    if (isJumpBarOpen()) {
      updateCount();
    }
  }

  function setTruncated(value: boolean): void {
    truncated = value;
    if (isJumpBarOpen()) {
      updateCount();
    }
  }

  return {
    isOpen: isJumpBarOpen,
    open: open,
    close: close,
    next: next,
    prev: prev,
    refresh: refresh,
    rebuild: rebuild,
    invalidate: invalidate,
    setTruncated: setTruncated,
    register: register,
  };
}

var _mmdJump = _createJumpController();

// Escape や、別のバーを開いたときの自動クローズはレジストリ経由で届く。
registerBar('jump', {
  close: function (): void {
    _mmdJump.close();
  },
});

// バーの閉じるボタンと前後ボタンを配線する（_mmdInit から 1 回だけ呼ぶ）。
function _mmdInitJump(): void {
  var strings: ViewerJumpStrings = window._mmdJumpStrings || {};
  var bar = document.getElementById('mmd-jump-bar');
  if (!bar) return;

  var prevButton = document.getElementById('mmd-jump-prev');
  var nextButton = document.getElementById('mmd-jump-next');
  var closeButton = document.getElementById('mmd-jump-close');

  if (prevButton) {
    if (strings.previous) prevButton.title = strings.previous;
    prevButton.addEventListener('click', function () {
      _mmdJump.prev();
    });
  }
  if (nextButton) {
    if (strings.next) nextButton.title = strings.next;
    nextButton.addEventListener('click', function () {
      _mmdJump.next();
    });
  }
  if (closeButton) {
    if (strings.close) closeButton.title = strings.close;
    closeButton.addEventListener('click', function () {
      _mmdJump.close();
    });
  }

  // Enter / Shift+Enter による前後移動はここでは配線しない。ジャンプバーは
  // 入力欄を持たずキーボードフォーカスが乗らないため、バー要素の keydown には
  // 届かない（実機で確認）。document 側の resolveJumpNavigationKey が担う。
}

// _mmdOpenJump は Swift(evaluateJavaScript)から名前で呼ばれる入口。
// next/prev は Swift からは呼ばれず、document の keydown ハンドラ（keyboard.ts）が使う。
// 検索側（_mmdFindNextIfOpen）と同じくバーが閉じている間は何もしない。
// 閉じる操作は Esc をバーレジストリ（closeCurrentBar）が拾うため、専用の入口を持たない。
function _mmdOpenJump(kind: string): void {
  _mmdJump.open(kind);
}

function _mmdJumpNextIfOpen(): void {
  if (!_mmdJump.isOpen()) return;
  _mmdJump.next();
}

function _mmdJumpPrevIfOpen(): void {
  if (!_mmdJump.isOpen()) return;
  _mmdJump.prev();
}

export type { JumpProvider, JumpTarget };
export { _mmdJump, _mmdInitJump, _mmdOpenJump, _mmdJumpNextIfOpen, _mmdJumpPrevIfOpen };
