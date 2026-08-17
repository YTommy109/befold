// HTML エスケープと data URI/base64 の変換。表示種別をまたいで共有する
// 文字列変換だけを置き、DOM には触らない。

// HTML 特殊文字をエスケープする。
function escapeHtml(text: unknown): string {
  return String(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

// SVG テキストを <img> の src に使える data URI にする。
// btoa は Latin-1 しか扱えないため、encodeURIComponent + unescape で
// UTF-8 バイト列を 1 バイト 1 文字の文字列へ均してから base64 化する。
function svgDataURI(svgText: string): string {
  return 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(svgText)));
}

// base64 の画像データを <img> の src に使える data URI にする。
// mimeType は Swift 側(ViewerBridge)が渡す実際の MIME。未指定時は
// 従来どおり image/png とみなす。
function imageDataURI(base64: string, mimeType: string | undefined): string {
  return 'data:' + (mimeType || 'image/png') + ';base64,' + base64;
}

// base64 文字列をバイト列へ復号する(PDF の Blob 生成用)。
// 戻り値を Uint8Array<ArrayBuffer> と明示するのは、既定の Uint8Array が
// SharedArrayBuffer 上のものも含み Blob へ直接渡せないため。ここで確保するのは
// 常に自前の ArrayBuffer なので、実行時の値は変わらない。
function base64ToBytes(base64: string): Uint8Array<ArrayBuffer> {
  var binary = atob(base64);
  var bytes = new Uint8Array(binary.length);
  for (var i = 0; i < binary.length; i++) {
    // atob が返すのは Latin-1 の 1 文字 = 1 バイトの文字列で、ここで欲しいのは
    // コードポイントではなくバイト値。codePointAt に替えるとサロゲートペアを
    // 1 つの値へ畳んでバイト列が壊れるため charCodeAt のままにする。
    // oxlint-disable-next-line unicorn/prefer-code-point
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export { escapeHtml, svgDataURI, imageDataURI, base64ToBytes };
