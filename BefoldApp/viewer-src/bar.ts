// 画面右上に出るバー（検索バー / 文書内ジャンプバー）の排他を 1 箇所で持つ。
//
// バーごとに「開いているか」のフラグを持たせると「両方開いている」状態が
// 型の上で表現可能になり、同時に開かないことが doc コメントだけの決めごとに
// なる。ここで「いま開いているのはどれか」を単一の値として持ち、
// 別のバーを開いた時点で前のバーを必ず閉じる（TASK-485.1 の設計判断）。
//
// find.ts と jump.ts が互いを import すると循環するため、各バーは自分の
// close 手続きをここへ登録し、閉じる指示はレジストリ経由で受け取る。

type BarKind = 'find' | 'jump';
type OpenBar = BarKind | null;

interface BarHandlers {
  close(): void;
}

var handlers: Partial<Record<BarKind, BarHandlers>> = {};
var openBar: OpenBar = null;

// 各バーのコントローラが生成時に自分を登録する。
function registerBar(kind: BarKind, barHandlers: BarHandlers): void {
  handlers[kind] = barHandlers;
}

// いま開いているバー。どれも開いていなければ null。
function currentBar(): OpenBar {
  return openBar;
}

function isBarOpen(kind: BarKind): boolean {
  return openBar === kind;
}

// kind を開いた状態にする。別のバーが開いていれば先に閉じる。
// 呼び出し側（各バーの open）は、この関数が返ってから自分の DOM を表示する。
function claimBar(kind: BarKind): void {
  if (openBar === kind) {
    return;
  }
  if (openBar !== null) {
    var previous = handlers[openBar];
    if (previous) {
      previous.close();
    }
  }
  openBar = kind;
}

// kind が開いていれば閉じた状態にする。既に別のバーが開いている場合は何もしない
// （閉じ遅れの close が、後から開いた別のバーの状態を消さないようにする）。
function releaseBar(kind: BarKind): void {
  if (openBar === kind) {
    openBar = null;
  }
}

// いま開いているバーを閉じる（Escape から使う）。
function closeCurrentBar(): void {
  if (openBar === null) {
    return;
  }
  var current = handlers[openBar];
  if (current) {
    current.close();
  }
}

export type { BarKind, OpenBar };
export { registerBar, currentBar, isBarOpen, claimBar, releaseBar, closeCurrentBar };
