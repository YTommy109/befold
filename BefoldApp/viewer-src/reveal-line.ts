// 指定行をソース表示の先頭へ出す(CLI の `--line`)。
//
// 行は「表示される前」に届くことがある(新規窓では描画より先、段階読み込みでは行が
// まだ DOM に無い)。そのため要求は文書パスつきで保留し、描画・追記・読み込み状態の
// 変化のたびに満たせるか試す。パスを持たせるのは、別の文書が採用されたときに
// 古い要求が新しい文書をスクロールさせないため(採用済みパスとの照合は
// doc-path.ts が単一の情報源)。

import { _mmdRequestMoreLines } from './bridge.js';
import { _mmdDocPath } from './doc-path.js';
import { _mmdDocument } from './document-state.js';

type RevealRequest = { path: string; line: number };

// 行を出せる形(ソースコード表示)の表を返す。DOM のクラスではなく render が記録した
// 形で判定する: 差分テーブルも table.code-table を名乗るため(TASK-318)。
function sourceTable(): HTMLTableElement | null {
  var shape = _mmdDocument.shape();
  if (shape !== 'code' && shape !== 'csv-source') {
    return null;
  }
  return document.querySelector<HTMLTableElement>('#diagram-wrap pre code table.code-table');
}

function _createLineReveal() {
  var pending: RevealRequest | null = null;
  // 続きの読み込みを依頼済みで、まだ何も届いていない間は重ねて依頼しない。
  var moreRequested = false;
  var truncated = false;
  var loadFailed = false;

  function scrollToRow(table: HTMLTableElement, line: number): void {
    var row = table.rows[Math.min(line, table.rows.length) - 1];
    if (row) {
      row.scrollIntoView({ block: 'start' });
    }
    pending = null;
  }

  // afterRender: render() の直後か。表がまだ無いだけの時点(要求が描画より先に届いた)
  // と、描画の結果この文書では出せないと分かった時点を区別するための印。
  function attempt(afterRender: boolean): void {
    if (!pending) {
      return;
    }
    var current = _mmdDocPath.current();
    if (current === null) {
      return;
    }
    if (current !== pending.path) {
      if (afterRender) {
        pending = null;
      }
      return;
    }
    var table = sourceTable();
    if (!table) {
      if (afterRender) {
        pending = null;
      }
      return;
    }
    if (pending.line <= table.rows.length || loadFailed) {
      scrollToRow(table, pending.line);
      return;
    }
    if (!truncated) {
      // 続きを依頼している間は、「末尾まで読んだ」通知が最後のチャンクの追記より先に届く
      // (Swift は読み込み状態を送ってから追記する)。ここで確定すると、まだ DOM に無い行を
      // 末尾へ寄せてしまう。追記(afterAppend)が来てから判断する。
      if (!moreRequested) {
        // 末尾まで読んでもその行が無ければ、末尾の行へ寄せる。
        scrollToRow(table, pending.line);
      }
      return;
    }
    if (!moreRequested) {
      moreRequested = true;
      if (!_mmdRequestMoreLines()) {
        scrollToRow(table, pending.line);
      }
    }
  }

  return {
    request: function (path: string, line: number): void {
      pending = { path: path, line: line };
      moreRequested = false;
      attempt(false);
    },
    afterRender: function (): void {
      // 続きの到着を待っている間の再描画は文書の内容が変わったということで、
      // 待っていた行はもう当てにならない。後の再描画で突然末尾へ飛ばないよう捨てる。
      if (moreRequested) {
        pending = null;
      }
      moreRequested = false;
      attempt(true);
    },
    afterAppend: function (): void {
      moreRequested = false;
      attempt(false);
    },
    truncationChanged: function (isTruncated: boolean, failed: boolean): void {
      truncated = isTruncated;
      loadFailed = failed;
      // moreRequested はここでは戻さない: 続きが届けば afterAppend が戻す。Swift は
      // チャンクの追記と読み込み状態の通知を続けて送るため、ここでも戻すと 1 チャンクごとに
      // 依頼が 2 回出る。
      attempt(false);
    },
  };
}

var _mmdLineReveal = _createLineReveal();

function _mmdRevealLine(path: string, line: number): void {
  _mmdLineReveal.request(path, line);
}

export { _mmdLineReveal, _mmdRevealLine };
