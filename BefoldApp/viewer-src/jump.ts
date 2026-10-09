// 文書内ジャンプ。文書順に並んだ目印（見出し・変更ブロック・関数定義など）の列を
// 前後に移動する。検索バーと同じ「列 + 現在位置 + n/N 表示」の形をとるが、
// 列の作り方だけが対象ごとに違うため、列挙は JumpProvider に委ねてここには持たない。
//
// 位置の算術は navigation.ts、バーの排他は bar.ts、印・件数の DOM 更新は
// jump-view.ts と共有する。

import { wireBarControls } from './bar-controls.js';
import { claimBar, isBarOpen, registerBar, releaseBar, updateOuterVisibility } from './bar.js';
import {
  collectJumpTargets,
  markTargets,
  moveCurrent,
  setPanelDisplay,
  unmarkTargets,
  updateJumpCount,
  updateOptionsVisibility,
} from './jump-view.js';
import type { JumpProvider, JumpTarget } from './jump-view.js';
import { keptMatchIndex, nextMatchIndex, prevMatchIndex } from './navigation.js';

interface JumpController {
  isOpen(): boolean;
  // いま開いている種類（'heading' / 'changeBlock'）。閉じていれば ''。
  // モード切替スイッチ（bar-mode.ts）が選択状態を表示するために読む。
  activeMode(): string;
  open(kind: string): void;
  close(): void;
  next(): void;
  prev(): void;
  // 描画・チャンク追記のあとに列を作り直す。位置は可能な限り維持する。
  // resetToFirst が真なら先頭へ戻す（表示モード切替時）。
  //
  // 描画の着地。バーの開閉に関わらず必ずここへ来るため（render.ts の
  // _mmdFindRefreshAfterRender は無条件に呼ぶ）、描画中フラグを下ろすのは
  // ここ 1 箇所でよい。立てるのは invalidate の 1 箇所。
  refresh(resetToFirst?: boolean): void;
  // 列挙の条件が変わったときに列を作り直す（見出しレベルのトグルなど）。
  // 列の同一性が変わるため現在位置は先頭へ戻す。
  //
  // 描画中は何もしない。render() は invalidate から着地の refresh までの間
  // DOM を差し替えている最中で、その途中の DOM から作った currentIndex を
  // 着地時の refresh が位置維持の入力に使ってしまう（表示は最終的に正しくなるが
  // 位置維持の意図だけが静かに壊れる）。着地時の refresh が新しい条件で作り直すので
  // ここでスキップしても取りこぼさない。判定は DOM の中身ではなく内部状態で行う。
  rebuild(): void;
  // 描画の開始時に列を捨てる。着地までの間、前の文書の n/N と
  // ハイライトが残らないようにする。
  //
  // DOM は既に差し替わっている場合があるため、クラスの取り外しは行わず
  // 列だけを捨てる（残ったクラスは古い DOM ごと消える）。
  // currentIndex はここでは捨てない。着地時の refresh が「可能な限り位置を
  // 維持する」ために前の位置を要るため（捨てると再描画のたびに先頭へ戻る）。
  // 列が空の間、件数表示は 0/0 になる（formatNavigationCount は件数 0 のとき
  // 現在位置を 0 として組み立てる）ので、表示上も前の位置は見えない。
  invalidate(): void;
  // いま使える目印の種類が変わったことを受け取る。開いている種類が使えなく
  // なっていたらバーを閉じる。判定そのものは Swift 側の
  // `ViewerCapabilities.canJump(to:)` が持ち、ここは結果を受け取るだけ（TASK-485.18）。
  //
  // 閉じているときは何もしない（close は冪等だが、releaseBar が他バーの状態を
  // 巻き込まないよう入口で弾く）。「使えるか」を JS 側で判定し直さないのは、
  // 同じ規則が Swift と JS の 2 箇所で育つのを避けるため。開くときの種類選択
  // （DocumentCommandController.toggleJump()）と同じ canJump(to:) の結果がここへ届く。
  closeUnlessAvailable(kinds: string[]): void;
  setTruncated(value: boolean): void;
  register(provider: JumpProvider): void;
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
  // いま現在位置の印が付いている要素。付け替えのたびに列全体を走査しないよう、
  // 直前に印を付けた要素だけを覚えておく（差分の変更行は数万件になりうる）。
  var currentHighlight: HTMLElement[] = [];
  // 段階読み込み中か。真のときは表示済み DOM の分しか数えられないことを件数表示で示す。
  var truncated = false;
  // 描画中（invalidate から着地の refresh まで）。rebuild の抑止用。立てる・下ろすは各 1 箇所。
  var isRendering = false;

  function register(provider: JumpProvider): void {
    providers[provider.id] = provider;
  }

  function updateCount(): void {
    updateJumpCount(providers[activeKind], currentIndex, targets.length, truncated);
  }

  function highlightCurrent(scroll: boolean): void {
    currentHighlight = moveCurrent(currentHighlight, targets[currentIndex], scroll);
  }

  // 目印の列から、候補と現在位置の印を両方取り除く。
  //
  // **列を捨てる経路はすべてこの関数を通す。** 列が入れ替わるのは open だけでなく
  // refresh（描画・チャンク追記・レベル変更）でも起きるため、片方の経路だけで
  // 外す形にすると古い候補の下線が残る。
  function clearHighlight(): void {
    currentHighlight = moveCurrent(currentHighlight, undefined, false);
    unmarkTargets(targets);
  }

  function moveTo(index: number, scroll: boolean): void {
    currentIndex = index;
    highlightCurrent(scroll);
    updateCount();
  }

  function run(scroll: boolean): void {
    clearHighlight();
    targets = collectJumpTargets(providers[activeKind]);
    markTargets(targets);
    currentIndex = targets.length > 0 ? 0 : -1;
    highlightCurrent(scroll);
    updateCount();
  }

  function open(kind: string): void {
    activeKind = kind;
    claimBar('jump');
    setPanelDisplay('flex');
    updateOptionsVisibility(providers, activeKind);
    run(true);
    // claimBar は「find/jump 間の切り替え」しか検知しない。jump 内で種類だけが
    // 変わる場合（見出し→変更箇所）は claimBar が早期リターンするため、
    // モード切替スイッチの選択表示を更新するにはここで明示的に伝える必要がある。
    updateOuterVisibility();
  }

  function close(): void {
    releaseBar('jump');
    setPanelDisplay('none');
    clearHighlight();
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
    isRendering = false;
    // 閉じている間は列を作らない。作ると候補の印（下線）が付いてしまう。
    if (!isJumpBarOpen()) {
      return;
    }
    var previousIndex = resetToFirst ? 0 : currentIndex;
    clearHighlight();
    targets = collectJumpTargets(providers[activeKind]);
    markTargets(targets);
    currentIndex = -1;
    if (targets.length > 0) {
      moveTo(keptMatchIndex(previousIndex, targets.length), false);
    } else {
      updateCount();
    }
  }

  function rebuild(): void {
    if (!isJumpBarOpen() || isRendering) {
      return;
    }
    refresh(true);
  }

  function invalidate(): void {
    isRendering = true;
    targets = [];
    // 覚えていた現在位置の要素も捨てる（古い DOM を指したままにしない）。
    currentHighlight = [];
    if (isJumpBarOpen()) {
      updateCount();
    }
  }

  function closeUnlessAvailable(kinds: string[]): void {
    if (!isJumpBarOpen() || kinds.includes(activeKind)) {
      return;
    }
    close();
  }

  function setTruncated(value: boolean): void {
    truncated = value;
    if (isJumpBarOpen()) {
      updateCount();
    }
  }

  function activeMode(): string {
    return isJumpBarOpen() ? activeKind : '';
  }

  return {
    isOpen: isJumpBarOpen,
    activeMode: activeMode,
    open: open,
    close: close,
    next: next,
    prev: prev,
    refresh: refresh,
    rebuild: rebuild,
    invalidate: invalidate,
    closeUnlessAvailable: closeUnlessAvailable,
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
  var bar = document.getElementById('mmd-jump-panel');
  if (!bar) return;

  var prevButton = document.getElementById('mmd-jump-prev');
  var nextButton = document.getElementById('mmd-jump-next');
  var closeButton = document.getElementById('mmd-jump-close');

  if (prevButton && strings.previous) prevButton.title = strings.previous;
  if (nextButton && strings.next) nextButton.title = strings.next;
  if (closeButton && strings.close) closeButton.title = strings.close;

  wireBarControls({
    prevId: 'mmd-jump-prev',
    nextId: 'mmd-jump-next',
    closeId: 'mmd-jump-close',
    onPrev: function () {
      _mmdJump.prev();
    },
    onNext: function () {
      _mmdJump.next();
    },
    onClose: function () {
      _mmdJump.close();
    },
  });

  // Enter / Shift+Enter による前後移動はここでは配線しない。ジャンプバーは
  // 入力欄を持たずキーボードフォーカスが乗らないため、バー要素の keydown には
  // 届かない（実機で確認）。document 側の resolveJumpNavigationKey が担う。
}

// _mmdOpenJump はモード切替（bar-mode.ts の openMode / _mmdToggleBarMode）が使う入口。
// Swift からは直接呼ばれない（⇧⌘F は _mmdToggleBarMode を通る / TASK-485.28）。
// next/prev は document の keydown ハンドラ（keyboard.ts）の Enter / Shift+Enter が使う。
// バーが閉じている間は何もしない。⌘G / ⇧⌘G は bar-mode.ts の _mmdBarNextIfOpen が
// _mmdJump.next / prev を直接呼ぶ（TASK-485.34）。
// 閉じる操作は Esc をバーレジストリ（closeCurrentBar）が拾うため、専用の入口を持たない。
function _mmdOpenJump(kind: string): void {
  _mmdJump.open(kind);
}

// 直近に届いた利用可能な種類。モード切替スイッチ（bar-mode.ts）が
// セグメントの表示/非表示を決めるために読む（TASK-485.19.3）。
// Swift からまだ一度も同期が届いていない間は「どれも使えない」として扱う
// （_mmdApplyJumpAvailability と同じ、閉じる方向へ倒す既定）。
var lastAvailableKinds: string[] = [];
var onAvailabilityChange: (() => void) | undefined;

// bar-mode.ts が「表示を更新したい」ことをここへ登録する（bar.ts の
// setOnBarChange と同じ理由: bar-mode.ts と互いに import すると循環する）。
function setOnAvailabilityChange(callback: () => void): void {
  onAvailabilityChange = callback;
}

function jumpAvailableKinds(): string[] {
  return lastAvailableKinds;
}

// Swift(evaluateJavaScript)から名前で呼ばれる入口。いま使えるジャンプの種類が
// 変わるたびに送られ、開いている種類が外れていればバーを閉じる。
function _mmdApplyJumpAvailability(kinds: unknown): void {
  // 配列以外（未注入・壊れた注入）は「どれも使えない」として扱う。バーを閉じる
  // 方向へ倒れるので、使えない種類のバーが残るより安全。
  var available = Array.isArray(kinds)
    ? kinds.filter(function (kind): kind is string {
        return typeof kind === 'string';
      })
    : [];
  lastAvailableKinds = available;
  // 閉じる判定を先に済ませてから通知する。モード切替スイッチが読む
  // currentMode() は「いま開いているか」を見るため、閉じたあとに通知しないと
  // 閉じたはずのモードが選択状態のまま表示される。
  _mmdJump.closeUnlessAvailable(available);
  if (onAvailabilityChange) {
    onAvailabilityChange();
  }
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
export {
  _mmdJump,
  _mmdInitJump,
  _mmdOpenJump,
  _mmdApplyJumpAvailability,
  _mmdJumpNextIfOpen,
  _mmdJumpPrevIfOpen,
  jumpAvailableKinds,
  setOnAvailabilityChange,
};
