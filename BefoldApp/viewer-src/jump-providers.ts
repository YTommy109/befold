// 目印の列挙。ジャンプの対象ごとにここへプロバイダを足す（TASK-485）。
// 列挙以外（位置・表示・スクロール）は jump.ts が持つので、ここには
// 「どれを目印とみなすか」と、それをユーザーが選ぶための配線だけを書く。
//
// レベル選択の状態とトグルの配線をここへ置くのは、jump.ts のコントローラが
// 「列挙の中身を知らない」という TASK-485.1 の決めごとを保つため。
// コントローラへ `setLevels` のような汎用口を開けると、対象ごとに違うオプションを
// 通す穴になり、列挙とそれ以外を分けた意味が薄れる。

import { _MSG_JUMP_LEVELS_CHANGED, _mmdPostMessage } from './bridge.js';
import { _mmdDocument } from './document-state.js';
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

// ATX 見出しの行。CommonMark に合わせて先頭空白は 3 つまで、# の直後には
// 空白（または行末）が要る。`#hashtag` や 4 つ以上の字下げ（＝コードブロック）を
// 見出しにしないための条件で、レンダリング表示の markdown-it と同じ判断になる。
var ATX_HEADING = /^ {0,3}(#{1,6})(?: |$)/u;

// フェンスの開始・終了。``` と ~~~ のどちらも、行頭空白 3 つまでを許す。
var CODE_FENCE = /^ {0,3}(`{3,}|~{3,})/u;

// ソース表示の 1 行のテキスト。行番号セルは別の <td> なので、行全体の
// textContent を使うと行番号が本文の先頭に混ざる（`1# title` のように読める）。
function sourceLineText(row: HTMLTableRowElement): string {
  return row.querySelector('.line-content')?.textContent ?? '';
}

// Markdown ソース表示の見出し行を、選んだレベルだけ文書順に拾う。
//
// フェンスの内外を上から順に持ち回るのは、コードブロックの中の `# コメント` を
// 見出しと誤検出しないため。行単位のパターン一致だけで決めると、シェルや
// Python のコメントがそのまま見出しになる（同型の実例: unified diff の
// ファイルヘッダ判定が削除行を巻き込んだ TASK-316）。
//
// 目印にするのは <tr> ではなく <td class="line-content">。border-collapse の表では
// tr への outline が上下辺しか描かれない（下の changeBlockJumpProvider と同じ実測）。
function collectSourceHeadings(root: HTMLElement): JumpTarget[] {
  var rows = root.querySelectorAll<HTMLTableRowElement>('tr');
  var targets: JumpTarget[] = [];
  var fence: string | null = null;
  rows.forEach(function (row) {
    var text = sourceLineText(row);
    var fenceMatch = CODE_FENCE.exec(text);
    if (fence !== null) {
      // 閉じるフェンスは開いたものと同じ文字で、同じ長さ以上でなければならない。
      if (fenceMatch && fenceMatch[1]![0] === fence[0] && fenceMatch[1]!.length >= fence.length) {
        fence = null;
      }
      return;
    }
    if (fenceMatch) {
      fence = fenceMatch[1]!;
      return;
    }
    var match = ATX_HEADING.exec(text);
    if (!match || !selectedLevels.includes(match[1]!.length)) {
      return;
    }
    var cell = row.querySelector<HTMLElement>('.line-content');
    if (cell) {
      targets.push({ anchor: cell, highlight: [cell] });
    }
  });
  return targets;
}

// レンダリング表示の見出し要素を拾う。
function collectRenderedHeadings(root: HTMLElement): JumpTarget[] {
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

// 見出しの列。ユーザーが選んだレベルを文書順に拾う。対象は 2 つあり、
// **Markdown レンダリング表示の h1 / h2 / h3** と
// **Markdown ソース表示の行頭 # / ## / ###**（TASK-485.17）。
//
// どちらを拾うかは `_mmdDocument.shape()`（render が実際に描いた形）だけで決める。
// 表示モードや type から推し直さず、DOM の形でも判定しない（document-state.ts の
// shape のコメント参照）。特に `table.code-table` を探す形は採れない
// ——差分テーブルも同じクラスを名乗るため（TASK-318 と同型）。shape が 'code' の
// ときだけソース行走査へ入るので、差分（'diff'）と CSV ソース（'csv-source'）は
// この分岐に入らない。
//
// レンダリング表示の見出しには markdown.ts の assignHeadingIds が既に id を
// 振っているが、ここでは id に依存せず要素そのものを目印にする（id は URL 断片用で、
// 目印の同一性とは別の関心）。
function collectHeadings(root: HTMLElement): JumpTarget[] {
  if (selectedLevels.length === 0) {
    return [];
  }
  if (_mmdDocument.shape() === 'code' && _mmdDocument.type() === 'md') {
    return collectSourceHeadings(root);
  }
  return collectRenderedHeadings(root);
}

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

// ソースコード表示の関数・型定義（TASK-485.4）。
//
// ## 判定を 2 つの役に分ける
//
// 「この行は定義の始まりか」は**行テキストの正規表現**で決め、
// 「その行は本当にコードか（コメント・文字列の中でないか）」は
// **hljs のスパン**で決める。
//
// 除外を自前の状態持ち回り（上の collectSourceHeadings が CODE_FENCE で
// やっている形）で書かないのは、4 言語へ広げるとブロックコメント・生文字列・
// ヒアドキュメント・テンプレートリテラルの規則を各言語ぶん抱えることになり、
// 「行単位のパターン一致だけで文脈を決める」形（TASK-316 と同型）へ戻るため。
// hljs は既にその字句解析をしており、`reflowSpanBalancedLines`（code-html.ts）が
// 行末で開いたままの span を閉じて次行の先頭で開き直すので、**複数行コメント／
// 文字列の途中の行も自分の td.line-content 内に hljs-comment / hljs-string を持つ**。
//
// 逆に `span.hljs-title.function_` を「定義である」ことの判定には使わない。
// JS/TS では呼び出し側（`foo(1)` / `obj.method(2)`）にも同じクラスが付き、
// 定義と区別できない（実測）。トークンは除外にだけ使う。
//
// ## 対応言語
//
// 非対応言語ではメニューごと無効になる（Swift 側 ViewerCapabilities）。
// この表と Swift の `FunctionJumpLanguages.supported` のずれは
// `ViewerFunctionJumpLanguageContractTests` が落とす。
//
// v1 では JS/TS のメソッド短縮記法（`foo() {`）を対象にしていない。
// `if (x) {` / `while (x) {` / `} catch (e) {` と行の形が同じで、除外語彙を
// 抱えないと誤検出するため。クラスメソッドを拾うのは別タスクとする。
var FUNCTION_JUMP_LANGUAGES = ['swift', 'python', 'javascript', 'typescript'];

// 言語ごとに 1 本へ結合した判定。collect は rebuild のたびに全行を走査するので、
// 行あたりに走らせる正規表現を増やさない（TASK-485.4 の設計レビュー項目 6）。
// `g` を付けないので `test` は状態を持たない（lastIndex の持ち越しが起きない）。
var JS_DEFINITION =
  /^\s*(?:export\s+)?(?:default\s+)?(?:declare\s+)?(?:abstract\s+)?(?:async\s+)?(?:function\b|class\s+[A-Za-z_$]|interface\s+[A-Za-z_$]|enum\s+[A-Za-z_$]|namespace\s+[A-Za-z_$]|type\s+[A-Za-z_$][\w$]*\s*[=<]|(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*(?::[^=]*)?=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*(?::[^=]*)?=>|[A-Za-z_$][\w$]*\s*=>))/u;

var DEFINITION_PATTERNS: Record<string, RegExp> = {
  // `class func` のように修飾子として現れる語も定義キーワードなので、
  // 修飾子の繰り返しは省略可能にしてある（`class Foo` は修飾子 0 個で一致する）。
  swift:
    /^\s*(?:(?:public|private|fileprivate|internal|open|package|static|class|final|override|mutating|nonmutating|convenience|required|dynamic|lazy|weak|unowned|indirect|nonisolated|isolated)\s+)*(?:func|class|struct|enum|protocol|extension|actor|init|deinit|subscript)\b/u,
  // デコレータは別の行にあるので def / class そのものに錨を下ろす。
  python: /^\s*(?:async\s+)?(?:def|class)\s+/u,
  javascript: JS_DEFINITION,
  typescript: JS_DEFINITION,
};

// いまの文書に使う判定。ソース表示（shape 'code'）でなければ null。
// 表示モードや DOM の形から推し直さないのは collectHeadings と同じ理由。
function definitionPattern(): RegExp | null {
  if (_mmdDocument.shape() !== 'code') {
    return null;
  }
  var lang = _mmdDocument.lang();
  // 対応言語の判定は FUNCTION_JUMP_LANGUAGES を必ず経由する。表の引き当てだけで
  // 済ませると、この配列が「エクスポートされているだけで誰も見ていない値」になり、
  // Swift 側との契約テストが実際の挙動を測らなくなる。
  if (lang === undefined || !FUNCTION_JUMP_LANGUAGES.includes(lang)) {
    return null;
  }
  return DEFINITION_PATTERNS[lang] ?? null;
}

// コメント・文字列を取り除いた、その行の実効的なコード。
// 行まるごとがブロックコメントの内側なら空文字になる。
//
// 直下の子だけを見れば足りる。reflowSpanBalancedLines が行頭で開き直すスパンは
// 行の最上位に来るため、「行がコメント／文字列の内側にある」ことは直下の子で表れる。
// clone してから remove する形を採らないのは、行数ぶんの DOM 複製を避けるため。
function codeTextOf(cell: HTMLElement): string {
  var text = '';
  cell.childNodes.forEach(function (node) {
    if (node instanceof HTMLElement && node.matches('.hljs-comment, .hljs-string')) {
      return;
    }
    text += node.textContent ?? '';
  });
  return text;
}

function collectFunctionDefinitions(root: HTMLElement): JumpTarget[] {
  var pattern = definitionPattern();
  if (!pattern) {
    return [];
  }
  var targets: JumpTarget[] = [];
  root.querySelectorAll<HTMLTableRowElement>('tr').forEach(function (row) {
    // 素のテキストで足切りしてから、候補になった行だけコメント・文字列を
    // 除いて再判定する。clone を全行に対して作ると段階読み込みのたびに
    // 行数ぶんの DOM 複製が走るため（rebuild は appendChunk ごとに呼ばれる）。
    if (!pattern.test(sourceLineText(row))) {
      return;
    }
    var cell = row.querySelector<HTMLElement>('.line-content');
    if (!cell) {
      return;
    }
    if (cell.querySelector('.hljs-comment, .hljs-string') && !pattern.test(codeTextOf(cell))) {
      return;
    }
    targets.push({ anchor: cell, highlight: [cell] });
  });
  return targets;
}

var functionDefinitionJumpProvider: JumpProvider = {
  id: 'functionDefinition',
  collect: collectFunctionDefinitions,
  // ignoresTruncation は付けない。差分表示と違いソース表示は appendChunk で
  // 実際に追記が起きるため、未読み込み範囲の定義は DOM に存在しない。
  // 「表示範囲内」ラベルはその事実をユーザーへ伝えるもので、消してはいけない。
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
  functionDefinitionJumpProvider,
  collectFunctionDefinitions,
  FUNCTION_JUMP_LANGUAGES,
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
