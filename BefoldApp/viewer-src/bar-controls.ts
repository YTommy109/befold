// 前へ/次へ/閉じるボタンのクリック配線。find.ts と jump.ts で同じパターン
// （getElementById → addEventListener('click', ...)）が重複していたため1箇所化する。
//
// find バー・jump バーの DOM は viewer.html に静的に置かれ常に存在するが、
// jump.ts は元々 null ガード付きで配線していたため、その挙動（要素が無ければ
// 何もしない）を踏襲する。find.ts 側もこれで挙動は変わらない
// （要素は常に存在するため、これまで `!` で表明していた箇所が実行時に
// 例外を投げる経路は元々到達しなかった）。

interface BarControlsConfig {
  prevId: string;
  nextId: string;
  closeId: string;
  onPrev(): void;
  onNext(): void;
  onClose(): void;
}

function wireBarControls(config: BarControlsConfig): void {
  var prevButton = document.getElementById(config.prevId);
  var nextButton = document.getElementById(config.nextId);
  var closeButton = document.getElementById(config.closeId);
  if (prevButton) {
    prevButton.addEventListener('click', config.onPrev);
  }
  if (nextButton) {
    nextButton.addEventListener('click', config.onNext);
  }
  if (closeButton) {
    closeButton.addEventListener('click', config.onClose);
  }
}

export { wireBarControls };
export type { BarControlsConfig };
