// バー右上のモード切替スイッチ（検索/見出し/変更箇所、TASK-485.19）。
//
// 実際の検索・列挙ロジックは持たない。クリックは既存の open 入口
// （_mmdOpenFind / _mmdOpenJump）へ委譲し、いま開いているモードに応じて
// スイッチの選択状態の見た目を揃えるだけの薄い調整役。外枠（#mmd-bar）の
// 表示・非表示は bar.ts が一元管理する（このモジュールは選択状態の
// ハイライトだけを担当する）。

import { currentBar, setOnBarChange } from './bar.js';
import { _mmdOpenFind } from './find.js';
import { _mmdJump, _mmdOpenJump } from './jump.js';

type BarMode = 'search' | 'heading' | 'changeBlock';

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

// バーの開閉・モードが変わるたびに呼ばれ、スイッチの選択表示を揃える
// （bar.ts の setOnBarChange から呼ばれる。外枠の表示自体は bar.ts が持つ）。
function updateSwitchAppearance(): void {
  var mode = currentMode();
  (Object.keys(MODE_BUTTON_IDS) as BarMode[]).forEach(function (key) {
    var button = document.getElementById(MODE_BUTTON_IDS[key]);
    if (button) {
      button.classList.toggle('active', key === mode);
    }
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
  (Object.keys(MODE_BUTTON_IDS) as BarMode[]).forEach(function (key) {
    var button = document.getElementById(MODE_BUTTON_IDS[key]);
    if (!button) return;
    button.addEventListener('click', function () {
      openMode(key);
    });
  });
}

export { _mmdInitBarModeSwitch };
