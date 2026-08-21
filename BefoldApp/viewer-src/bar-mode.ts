// バー右上のモード切替スイッチ（検索/見出し/変更箇所、TASK-485.19）。
//
// 実際の検索・列挙ロジックは持たない。クリックは既存の open 入口
// （_mmdOpenFind / _mmdOpenJump）へ委譲し、いま開いているモードに応じて
// スイッチの選択状態の見た目を揃えるだけの薄い調整役。外枠（#mmd-bar）の
// 表示・非表示は bar.ts が一元管理する（このモジュールは選択状態の
// ハイライトだけを担当する）。

import { currentBar, setOnBarChange } from './bar.js';
import { _mmdOpenFind } from './find.js';
import { _mmdJump, _mmdOpenJump, jumpAvailableKinds, setOnAvailabilityChange } from './jump.js';

type BarMode = 'search' | 'heading' | 'changeBlock';

var MODES: readonly BarMode[] = ['search', 'heading', 'changeBlock'];

var MODE_BUTTON_IDS: Record<BarMode, string> = {
  search: 'mmd-bar-mode-search',
  heading: 'mmd-bar-mode-heading',
  changeBlock: 'mmd-bar-mode-changeBlock',
};

// いま選ばれているモード。バーが閉じていれば null。
function currentMode(): BarMode | null {
  var bar = currentBar();
  if (bar === 'find') {
    return 'search';
  }
  if (bar === 'jump') {
    var kind = _mmdJump.activeMode();
    return kind === 'heading' || kind === 'changeBlock' ? kind : null;
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

function _mmdInitBarModeSwitch(): void {
  setOnBarChange(updateSwitchAppearance);
  setOnAvailabilityChange(updateSwitchAppearance);
  // Swift からの最初の可用性同期が届く前でも、検索は常時使えるためスイッチの
  // 初期状態(見出し/変更箇所を隠す)を合わせておく。
  updateSwitchAppearance();
  MODES.forEach(function (key) {
    var button = document.getElementById(MODE_BUTTON_IDS[key]);
    if (!button) return;
    button.addEventListener('click', function () {
      openMode(key);
    });
  });
}

export { _mmdInitBarModeSwitch };
