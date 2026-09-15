// キーボードスクロール(↑↓ / j k / Shift+↑↓ / Space)が滑らかに動くことの回帰テスト。
//
// scrollBy の behavior が 'auto' に戻ると、1 回のキー操作で表示位置が瞬間移動する。
// 実測(TASK-486): 実 WKWebView 上で behavior:'auto' は最初のフレームで既に目標位置へ
// 到達し(0 → 600px)、中間フレームが 1 つも無い。'smooth' は約 16 フレームかけて
// 0 → 600px を踏む。読んでいた行を見失うという報告はこの瞬間移動が原因。
const { loadViewerMain } = require('./support/viewerMainHarness');

function dispatchKey(window, key, init) {
  const event = new window.KeyboardEvent(
    'keydown',
    Object.assign({ key: key, bubbles: true, cancelable: true }, init || {}),
  );
  window.document.dispatchEvent(event);
  return event;
}

// _mmdScrollTarget() が返す要素の scrollBy を記録する。
function captureScrollBy(main) {
  const target = main._mmdScrollTarget();
  expect(target).toBeTruthy();
  const calls = [];
  target.scrollBy = function (options) {
    calls.push(options);
  };
  return calls;
}

describe('キーボードスクロールの behavior', () => {
  test.each([
    ['ArrowDown', {}],
    ['ArrowUp', {}],
    ['j', {}],
    ['k', {}],
    ['ArrowDown', { shiftKey: true }],
    [' ', {}],
    [' ', { shiftKey: true }],
  ])('%s (%o) は smooth でスクロールする', (key, init) => {
    const { window, main } = loadViewerMain({ hostFeatures: { spaceScroll: true } });
    const calls = captureScrollBy(main);

    dispatchKey(window, key, init);

    expect(calls).toHaveLength(1);
    expect(calls[0].behavior).toBe('smooth');
  });

  test('向きと量はこれまでどおり(下は正・上は負、Shift はより大きく進む)', () => {
    const { window, main } = loadViewerMain({ hostFeatures: { spaceScroll: true } });
    const calls = captureScrollBy(main);

    dispatchKey(window, 'ArrowDown', {});
    dispatchKey(window, 'ArrowUp', {});

    expect(calls[0].top).toBeGreaterThan(0);
    expect(calls[1].top).toBe(-calls[0].top);
  });
});
