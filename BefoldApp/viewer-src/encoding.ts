// HTML エスケープと data URI/base64 の変換。表示種別をまたいで共有する
// 文字列変換だけを置き、DOM には触らない。

// HTML 特殊文字をエスケープする。
function escapeHtml(text: unknown): string {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
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
function base64ToBytes(base64: string): Uint8Array {
  var binary = atob(base64);
  var bytes = new Uint8Array(binary.length);
  for (var i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export { escapeHtml, svgDataURI, imageDataURI, base64ToBytes };
