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
//
// 受け取るのは公開面の barrel（main.js）1 つだけにしてある。可変長にすると
// 呼び出し側ごとに違うモジュールの組み合わせを渡せてしまい、本番とテストで
// グローバルに載る集合がずれても気づけない。
//
// 引数の型は「名前 → 値」の対応だけを要求する（TASK-432.4）。barrel の具体型に
// してしまうと、モジュールを 1 つ足すたびにここの型も直す形になり、
// 「追記漏れを作らない」という上の設計意図と衝突する。
export function exposeGlobals(namespace: Record<string, unknown>): void {
  for (const [name, value] of Object.entries(namespace)) {
    (globalThis as Record<string, unknown>)[name] = value;
  }
}
