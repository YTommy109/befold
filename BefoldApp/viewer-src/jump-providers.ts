// 目印の列挙。ジャンプの対象ごとにここへプロバイダを足す（TASK-485）。
// 列挙以外（位置・表示・スクロール）は jump.ts が持つので、ここには
// 「どれを目印とみなすか」と、それをユーザーが選ぶための配線だけを書く。
//
// レベル選択の状態とトグルの配線をここへ置くのは、jump.ts のコントローラが
// 「列挙の中身を知らない」という TASK-485.1 の決めごとを保つため。
// コントローラへ `setLevels` のような汎用口を開けると、対象ごとに違うオプションを
// 通す穴になり、列挙とそれ以外を分けた意味が薄れる。

import { _MSG_JUMP_LEVELS_CHANGED, _mmdPostMessage } from './bridge.js';
import { _mmdJump } from './jump.js';
import type { JumpProvider, JumpTarget } from './jump.js';

// 選べる見出しレベルと、その UI の対応。
// h4 以降を含めないのは、節の移動という用途に対して目印が細かくなりすぎるため。
// h1 は文書題名が 1 つあるだけの文書だと「1/1」にしかならないが、
// h1 を複数持つ文書があるためユーザーの選択に委ねる（TASK-485.2）。
var HEADING_LEVELS = [1, 2, 3];

// いま目印にするレベル。既定は 3 つとも。Swift が注入した保存値があれば
// _mmdInitHeadingLevels が上書きする。
var selectedLevels: number[] = HEADING_LEVELS.slice();

function levelButtonId(level: number): string {
  return 'mmd-jump-level-h' + level;
}

// 選択中のレベルから CSS セレクタを組む。1 つも選んでいなければ null
// （呼び出し側は列を空にする。「選んでいない」は正当な状態で、
// 文書に見出しが無いこととは別）。
function headingSelector(levels: number[]): string | null {
  if (levels.length === 0) {
    return null;
  }
  return levels
    .map(function (level) {
      return 'h' + level;
    })
    .join(', ');
}

function collectHeadings(root: HTMLElement): JumpTarget[] {
  var selector = headingSelector(selectedLevels);
  if (!selector) {
    return [];
  }
  var elements = root.querySelectorAll<HTMLElement>(selector);
  var targets: JumpTarget[] = [];
  elements.forEach(function (element) {
    targets.push({ anchor: element, highlight: [element] });
  });
  return targets;
}

// 見出しの列。Markdown レンダリング表示の h1 / h2 / h3 のうち、
// ユーザーが選んだレベルを文書順に拾う。
//
// 見出しには markdown.ts の assignHeadingIds が既に id を振っているが、
// ここでは id に依存せず要素そのものを目印にする（id は URL 断片用で、
// 目印の同一性とは別の関心）。
var headingJumpProvider: JumpProvider = {
  id: 'heading',
  collect: collectHeadings,
  isSelectionEmpty: function (): boolean {
    return selectedLevels.length === 0;
  },
  optionsElementId: 'mmd-jump-levels',
};

// 差分表示の変更ブロック（TASK-485.3）。
//
// DOM のクラスからは数えない。インライン表示では tr に diff-add / diff-del が付くが、
// 左右分割では側セル（td.diff-side）へ付くため、レイアウトごとに列挙の形が変わり
// 「同じ差分なのに件数が違う」経路ができる。代わりに diff-html.ts が描画時に
// 割り当てた data-diff-block を読む。番号はどちらのレイアウトでも同じ
// hunk.lines から振られるので、数と順序が一致することは構造で保証される。
//
// アクティブな印は「ブロックの各行の左端セル」へ付ける。CSS 側が左辺だけの
// インセット影にしてあるので、複数行のブロックでも 1 本の縦帯に見える。
// 行（tr）に当てないのは、border-collapse の表では tr への outline が上下辺しか
// 描かれないため（TASK-485.1 の実測）。囲みや全セルの枠にしないのは、変更行が
// 既に地色で見えているところへ線を足すと画面が賑やかになりすぎるため。
function collectChangeBlocks(root: HTMLElement): JumpTarget[] {
  var rows = root.querySelectorAll<HTMLElement>('[data-diff-block]');
  var targets: JumpTarget[] = [];
  var currentBlock: string | undefined;
  rows.forEach(function (row) {
    var block = row.dataset['diffBlock'];
    if (block === undefined) return;
    var edge = leadingCell(row);
    if (block === currentBlock) {
      // 同じブロックの 2 行目以降。目印は増やさず、帯を伸ばすだけ。
      // concat で配列を作り直さず push で伸ばす（作り直すとブロック行数 k に対して
      // O(k^2) になる。全面書き換えの差分は 1 ブロックが数千〜数万行になりうる）。
      var previous = targets.at(-1);
      if (previous) {
        previous.highlight.push(...edge);
        return;
      }
    }
    currentBlock = block;
    targets.push({ anchor: row, highlight: edge });
  });
  return targets;
}

// 行の左端のセル。インラインなら最初の行番号セル（行番号を出していない表では記号セル）、
// 左右分割なら左側のペイン。帯はここへ引く。
function leadingCell(row: HTMLElement): HTMLElement[] {
  var first = row.firstElementChild;
  return first instanceof HTMLElement ? [first] : [];
}

var changeBlockJumpProvider: JumpProvider = {
  id: 'changeBlock',
  collect: collectChangeBlocks,
  // 差分表示中は appendChunk が追記をスキップし、差分の表は setDiff で渡った
  // 全文から組まれる。本文が段階読み込み中でも変更ブロックは全数そろっている。
  ignoresTruncation: true,
};

// いま選ばれているレベル（テストが読む）。
function selectedHeadingLevels(): number[] {
  return selectedLevels.slice();
}

// 保存・注入で使う表現（["h1","h3"] 形式）。Swift の HeadingJumpLevels.storedValue と対。
function headingLevelTokens(): string[] {
  return selectedLevels.map(function (level) {
    return 'h' + level;
  });
}

// レベル集合を差し替え、ボタンの見た目を揃える。列の作り直しはしない
// （呼び出し側が rebuild を頼む）。
function applyHeadingLevels(levels: number[]): void {
  selectedLevels = HEADING_LEVELS.filter(function (level) {
    return levels.includes(level);
  });
  HEADING_LEVELS.forEach(function (level) {
    var button = document.getElementById(levelButtonId(level));
    if (button) {
      button.classList.toggle('active', selectedLevels.includes(level));
    }
  });
}

// トグルを 1 つ反転し、Swift へ保存を依頼して列を作り直す。
// 3 つとも OFF も正当な状態として許す（最低 1 つを強制すると
// 「OFF にしたのに戻る」挙動になり、トグルの意味が壊れる）。
function toggleHeadingLevel(level: number): void {
  var next = selectedLevels.includes(level)
    ? selectedLevels.filter(function (selected) {
        return selected !== level;
      })
    : selectedLevels.concat([level]);
  applyHeadingLevels(next);
  // Swift へは保存表現（"h1" 形式）で送る。注入される window._mmdInitialJumpLevels と
  // 同じ形にしておかないと、受け手が解釈できず「3 つとも OFF」として保存される。
  _mmdPostMessage(_MSG_JUMP_LEVELS_CHANGED, { levels: headingLevelTokens() });
  // 列の同一性が変わるので現在位置は先頭へ戻す（rebuild が担う）。
  _mmdJump.rebuild();
}

// トグルを生成し、保存済みのレベル（Swift が注入）を反映する。
// バー要素が無い環境でもレベル状態は確定させる（buildLevelButtons が何もせず
// 戻るだけで、applyHeadingLevels は必ず走る。既定へ静かに縮退させない）。
function _mmdInitHeadingLevels(): void {
  buildLevelButtons();

  var initial = window._mmdInitialJumpLevels;
  applyHeadingLevels(
    Array.isArray(initial)
      ? initial
          .map(function (token) {
            return headingLevelNumber(token);
          })
          .filter(function (level) {
            return isLevel(level);
          })
      : HEADING_LEVELS,
  );
}

// レベルのトグルを HEADING_LEVELS から生成する。viewer.html へ静的に並べない
// のは、選べるレベルの集合が HTML と JS に独立して存在する状態を作らないため
// （片方だけ増やしても何も落ちない形になる。TASK-485.11）。
// Swift の HeadingJumpLevels.selectableLevels とのずれは
// ViewerBridgeContractTests が落とす。
function buildLevelButtons(): void {
  var element = document.getElementById('mmd-jump-levels');
  if (!element) return;
  var container = element;
  container.textContent = '';

  var strings: ViewerJumpStrings = window._mmdJumpStrings || {};
  HEADING_LEVELS.forEach(function (level) {
    var button = document.createElement('button');
    button.id = levelButtonId(level);
    button.className = 'mmd-find-toggle';
    button.textContent = 'H' + level;
    var title = strings.headingLevel;
    if (title) {
      button.title = title.replace('{level}', String(level));
    }
    button.addEventListener('click', function () {
      toggleHeadingLevel(level);
    });
    container.append(button);
  });
}

// 'h2' 形式の保存表現からレベル番号へ。Swift 側の HeadingJumpLevels.storedValue と対。
function headingLevelNumber(token: string): number {
  return Number(token.replace('h', ''));
}

function isLevel(level: number): boolean {
  return HEADING_LEVELS.includes(level);
}

export {
  headingJumpProvider,
  changeBlockJumpProvider,
  collectChangeBlocks,
  headingLevelTokens,
  toggleHeadingLevel,
  _mmdInitHeadingLevels,
  collectHeadings,
  headingSelector,
  selectedHeadingLevels,
  applyHeadingLevels,
  HEADING_LEVELS,
};
