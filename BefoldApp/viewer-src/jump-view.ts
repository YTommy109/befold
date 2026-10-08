// ジャンプバーの表示まわり（印・件数・オプション表示）。状態は持たず、
// jump.ts のコントローラが持つ状態を引数で受けて DOM を更新する。

import { formatNavigationCount, moveCurrentHighlight } from './navigation.js';

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

var CURRENT_CLASS = 'mmd-jump-current';
// 目印の候補であることを示すクラス。バーを開いている間だけ付き、
// 次にどこへ飛べるかをユーザーへ見せる（TASK-485.2）。
var TARGET_CLASS = 'mmd-jump-target';

// 目印の候補すべてに印を付ける。
function markTargets(targets: JumpTarget[]): void {
  targets.forEach(function (target) {
    target.highlight.forEach(function (element) {
      element.classList.add(TARGET_CLASS);
    });
  });
}

// 目印の列から候補の印を取り除く。
function unmarkTargets(targets: JumpTarget[]): void {
  targets.forEach(function (target) {
    target.highlight.forEach(function (element) {
      element.classList.remove(TARGET_CLASS);
    });
  });
}

// 現在位置の印を previous から current へ付け替え、新しく印を付けた要素の列を返す。
// scroll は next/prev/open のときだけ真にする。再構築（refresh）で毎回スクロールすると、
// 段階読み込み中にチャンクが届くたび読んでいる位置を奪ってしまう（appendChunk 経路には
// スクロール復元が無い）。
function moveCurrent(
  previous: HTMLElement[],
  current: JumpTarget | undefined,
  scroll: boolean,
): HTMLElement[] {
  var highlight = current ? current.highlight : [];
  moveCurrentHighlight(previous, highlight, CURRENT_CLASS, scroll ? current?.anchor : undefined);
  return highlight;
}

// 件数表示を更新する。
// 「表示範囲内」は"まだ読んでいない範囲は数えられていない"という意味なので、
// 目印の種類そのものが選ばれていないとき（列挙の条件で 0 件）は出さない。
// 段階読み込み中でも 0 件の原因は読み込み範囲ではないため、事実と食い違う。
function updateJumpCount(
  provider: JumpProvider | undefined,
  currentIndex: number,
  total: number,
  truncated: boolean,
): void {
  var countEl = document.getElementById('mmd-jump-count');
  if (!countEl) return;
  var strings: ViewerJumpStrings = window._mmdJumpStrings || {};
  var showsTruncatedLabel =
    truncated && provider?.isSelectionEmpty?.() !== true && provider?.ignoresTruncation !== true;
  countEl.textContent = formatNavigationCount(
    currentIndex,
    total,
    showsTruncatedLabel,
    strings.withinDisplayedRange || 'Displayed range',
  );
}

// バー内のオプション要素を、いま有効な対象のものだけ表示する。
// 登録済みのプロバイダを全部走査するのは、対象を切り替えたときに
// 前の対象のオプションが残らないようにするため（open のたびに全消し→1 つ表示）。
function updateOptionsVisibility(
  providers: Record<string, JumpProvider>,
  activeKind: string,
): void {
  Object.keys(providers).forEach(function (id) {
    var elementId = providers[id]?.optionsElementId;
    if (!elementId) return;
    var element = document.getElementById(elementId);
    if (!element) return;
    element.style.display = id === activeKind ? 'flex' : 'none';
  });
}

// 目印の列を作り直す。列挙はプロバイダに委ねる。
function collectJumpTargets(provider: JumpProvider | undefined): JumpTarget[] {
  var root = document.getElementById('diagram-wrap');
  if (!provider || !root) {
    return [];
  }
  return provider.collect(root);
}

function setPanelDisplay(display: string): void {
  var bar = document.getElementById('mmd-jump-panel');
  if (bar) {
    bar.style.display = display;
  }
}

export type { JumpProvider, JumpTarget };
export {
  collectJumpTargets,
  markTargets,
  unmarkTargets,
  moveCurrent,
  updateJumpCount,
  updateOptionsVisibility,
  setPanelDisplay,
};
