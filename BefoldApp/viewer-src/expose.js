// バンドルの公開関数をグローバルへ載せ直す処理（TASK-432.2）。
//
// ESM 化前は classic script のトップレベル関数宣言がそのままグローバルになり、
// Swift 側は `evaluateJavaScript("_mmdZoomIn()")` のような裸の呼び出しで到達できた
// （ViewerBridge.PlainFunction.callScript）。バンドルは IIFE なので、明示的に
// 載せ直さないとこの到達経路が失われる。
//
// 本番エントリ(index.js)とテストハーネスの双方がここを通ることで、
// 「テストでは見えるが本番では window に無い」ずれが生まれない。
//
// 個別列挙ではなく名前空間オブジェクトを反復するのは、公開関数を追加したときの
// 追記漏れで実行時まで気づけない形を作らないため（export した時点で載る）。
export function exposeGlobals(...namespaces) {
  for (const namespace of namespaces) {
    for (const [name, value] of Object.entries(namespace)) {
      globalThis[name] = value;
    }
  }
}
