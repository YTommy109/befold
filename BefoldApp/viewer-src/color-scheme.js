// OS のカラースキーム(ダークモード)の現在値と、その変更通知を提供する。
//
// matchMedia は初回参照時に一度だけ作る。分割前は初期化関数が代入するまで null で、
// 「代入前に mermaid を描画する経路はない」という暗黙の前提に乗っていた。
// 遅延生成にすることでその前提自体を無くし、参照側は初期化順を気にしなくてよくなる。

var darkQuery = null;

function query() {
  if (darkQuery === null) {
    darkQuery = window.matchMedia('(prefers-color-scheme: dark)');
  }
  return darkQuery;
}

// 現在ダークモードかどうか。
function prefersDark() {
  return query().matches;
}

// カラースキームの変更を購読する。登録は初期化時(init.js)に 1 回だけ行う。
function onColorSchemeChange(handler) {
  query().addEventListener('change', handler);
}

export { prefersDark, onColorSchemeChange };
