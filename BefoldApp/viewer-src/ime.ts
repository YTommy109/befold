// IME（日本語入力）の変換中かどうかの判定。

// 変換中の keydown が持つ keyCode。Safari/WKWebView は compositionend → keydown の
// 順で発火するため、変換確定の Enter では isComposing が既に false になっている。
// keyCode だけは 229 のまま残るので、これも併せて見ないと確定の Enter を
// 「素の Enter」として処理してしまう。
var IME_KEY_CODE = 229;

// 変換中（または変換確定直後）の keydown か。検索バーの Enter・ジャンプバーの
// Enter / Shift+Enter・Escape によるバーの close の 3 箇所が同じ規則で判定する。
function isComposingKeyEvent(event: { isComposing: boolean; keyCode: number }): boolean {
  return event.isComposing || event.keyCode === IME_KEY_CODE;
}

export { isComposingKeyEvent };
