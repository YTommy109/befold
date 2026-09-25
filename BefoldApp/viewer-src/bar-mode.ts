// バー右上のモード切替スイッチ（検索/見出し/変更箇所、TASK-485.19）。
//
// 実際の検索・列挙ロジックは持たない。クリックは既存の open 入口
// （_mmdOpenFind / _mmdOpenJump）へ委譲し、Swift からの ⌘F / ⇧⌘F は
// _mmdToggleBarMode（開閉のトグル）を通る。いま開いているモードに応じて
// スイッチの選択状態の見た目を揃えるだけの薄い調整役。外枠（#mmd-bar）の
// 表示・非表示は bar.ts が一元管理する（このモジュールは選択状態の
// ハイライトだけを担当する）。

import { closeCurrentBar, currentBar, setOnBarChange } from './bar.js';
import { _mmdOpenFind } from './find.js';
import { _mmdJump, _mmdOpenJump, jumpAvailableKinds, setOnAvailabilityChange } from './jump.js';

type BarMode = 'search' | 'heading' | 'changeBlock' | 'functionDefinition';

// 検索以外のモード名は Swift の DocumentJumpKind.rawValue と一対一。
// **モードの列挙はこの配列だけが持つ**（Swift の ViewerBridge.barModes は
// 契約テストでこの配列との一致を検査される）。 種類を足すときに触る場所を 1 つに
// 保つためで、かつて currentMode() が `kind === 'heading' || kind === 'changeBlock'`
// と独立に列挙しており、Swift 側が allCases で自動追随するのに対して
// ここだけ取り残される形だった（TASK-485.4 の設計レビュー）。
var MODES: readonly BarMode[] = ['search', 'heading', 'changeBlock', 'functionDefinition'];

var MODE_BUTTON_IDS: Record<BarMode, string> = {
  search: 'mmd-bar-mode-search',
  heading: 'mmd-bar-mode-heading',
  changeBlock: 'mmd-bar-mode-changeBlock',
  functionDefinition: 'mmd-bar-mode-functionDefinition',
};

// ジャンプの種類名（DocumentJumpKind.rawValue）をモードへ引き当てる。
// 該当が無ければ null（バーが閉じている、または未知の種類）。
function jumpMode(kind: string): BarMode | null {
  return (
    MODES.find(function (mode) {
      return mode !== 'search' && mode === kind;
    }) ?? null
  );
}

// いま選ばれているモード。バーが閉じていれば null。
function currentMode(): BarMode | null {
  var bar = currentBar();
  if (bar === 'find') {
    return 'search';
  }
  if (bar === 'jump') {
    return jumpMode(_mmdJump.activeMode());
  }
  return null;
}

// 検索は canFind が常時 true という前提（/review-design の結論）で、
// 可否判定は持たない。見出し/変更箇所は Swift 側 ViewerCapabilities.canJump(to:)
// 由来の availableKinds（TASK-485.18 の可用性伝搬を流用）で決まる。
function isModeAvailable(mode: BarMode): boolean {
  return mode === 'search' || jumpAvailableKinds().includes(mode);
}

// バーの開閉・モード・可用性が変わるたびに呼ばれ、スイッチの選択表示と
// 非対応セグメントの非表示を揃える（bar.ts の setOnBarChange、jump.ts の
// setOnAvailabilityChange から呼ばれる。外枠の表示自体は bar.ts が持つ）。
function updateSwitchAppearance(): void {
  var mode = currentMode();
  MODES.forEach(function (key) {
    var button = document.getElementById(MODE_BUTTON_IDS[key]);
    if (!button) return;
    button.classList.toggle('active', key === mode);
    button.style.display = isModeAvailable(key) ? '' : 'none';
  });
}

function openMode(mode: BarMode): void {
  if (mode === 'search') {
    _mmdOpenFind();
  } else {
    _mmdOpenJump(mode);
  }
}

// Swift(evaluateJavaScript)から名前で呼ばれる入口。⌘F / ⇧⌘F のトグル(TASK-485.28)。
// mode は 'search' か DocumentJumpKind.rawValue。
//
// 同じモードで開いていれば閉じ、閉じていれば開き、別のモードで開いていれば
// そのモードへ切り替える(閉じない)。開閉の状態は bar.ts だけが持ち、Swift は
// 写しを持たない——判定をここに置くのはそのため。
// モード切替スイッチのボタンは openMode を直接呼ぶので、押しても閉じない。
function _mmdToggleBarMode(mode: string): void {
  var target: BarMode | null = mode === 'search' ? 'search' : jumpMode(mode);
  if (target === null) {
    return;
  }
  if (currentMode() === target) {
    closeCurrentBar();
    return;
  }
  openMode(target);
}

function _mmdInitBarModeSwitch(): void {
  var labels = (window._mmdUIStrings || {}).modes || {};
  setOnBarChange(updateSwitchAppearance);
  setOnAvailabilityChange(updateSwitchAppearance);
  // Swift からの最初の可用性同期が届く前でも、検索は常時使えるためスイッチの
  // 初期状態(見出し/変更箇所を隠す)を合わせておく。
  updateSwitchAppearance();
  MODES.forEach(function (key) {
    var button = document.getElementById(MODE_BUTTON_IDS[key]);
    if (!button) return;
    // ラベルは ViewerBridge.uiStringsScript が viewer.mode.<モード名> から引いて渡す。
    // 未注入なら viewer.html の静的な英語のまま（キーの漏れは Swift の契約テストが捕まえる）。
    var label = labels[key];
    if (label) {
      button.textContent = label;
      button.title = label;
    }
    button.addEventListener('click', function () {
      openMode(key);
    });
  });
}

export { _mmdInitBarModeSwitch, _mmdToggleBarMode };
