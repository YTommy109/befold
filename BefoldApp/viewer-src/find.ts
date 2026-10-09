// 検索バー。クエリ・トグル・ヒット一覧・現在位置・開閉・段階読み込み中の
// すべてをコントローラのクロージャに閉じ、外部からは公開メソッド経由でのみ触れる。

import { claimBar, isBarOpen, registerBar, releaseBar } from './bar.js';
import { _MSG_FIND_OPTIONS_CHANGED, _mmdPostMessage } from './bridge.js';
import {
  applyFindHostSettings,
  findInputElement,
  moveFindHighlight,
  renderFindCount,
  searchDocument,
  wireFindControls,
} from './find-host.js';
import { buildFindRegExp, clearMarks } from './find-scan.js';
import type { FindOptions } from './find-scan.js';
import { keptMatchIndex, nextMatchIndex, prevMatchIndex } from './navigation.js';

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

// 開閉状態は bar.ts が一元管理する（検索バーとジャンプバーは同時に開かない）。
function isFindBarOpen(): boolean {
  return isBarOpen('find');
}

// 検索欄にキー入力が届く状態か。activeElement だけでは足りない:
// サイドバーへ移っても WebView 内の activeElement は入力欄のまま残るため、
// 文書自体がフォーカスを持つか（hasFocus）も併せて見る（TASK-485.29）。
function isFindInputFocused(): boolean {
  return document.hasFocus() && document.activeElement === findInputElement();
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

  // 現在位置の表示（件数）。状態はここに閉じているので、描画は find-host.ts へ渡す。
  function updateCount(): void {
    renderFindCount(query, currentIndex, matches.length, truncated);
  }

  function highlightCurrent(): void {
    var current = matches[currentIndex];
    moveFindHighlight(currentHighlight, current);
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
    query = findInputElement().value;
    clearMarks();
    currentIndex = -1;
    currentHighlight = undefined;
    matches = searchDocument(query, options);

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

  function applyHostSettings(): void {
    applyFindHostSettings(options);
  }

  function initControls(): void {
    wireFindControls({
      run: run,
      next: next,
      prev: prev,
      close: close,
      toggleOption: toggleOption,
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

// 以下は名前で公開する入口で、コントローラへの委譲だけを行う。Swift が
// evaluateJavaScript で直接呼ぶものは無い。⌘F は _mmdToggleBarMode を通り
// （TASK-485.28）、_mmdOpenFind はそこ（bar-mode.ts の openMode）から使われる。
// ⌘G / ⇧⌘G は bar-mode.ts の _mmdBarNextIfOpen / _mmdBarPrevIfOpen が
// 開いているバーを見て _mmdFind.next / prev へ振り分ける（TASK-485.34）。
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

export {
  buildFindRegExp,
  _mmdFind,
  _mmdInitFind,
  _mmdOpenFind,
  _mmdCloseFind,
  _mmdFindRefresh,
  isFindInputFocused,
};
