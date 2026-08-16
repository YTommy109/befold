// 直近に描画した内容とチャンク境界を保持する。

// 直近に描画した内容(カラースキーム変更時の再描画と、追記チャンクへ渡す前方文脈の
// 取得元)。書き手は render() の record() と appendChunk() の append() の 2 つだけで、
// 読み手は必ずアクセサ経由になる。type は mermaid のパースエラー表示でも読むため、
// 初回描画前は mmd(既定の表示型)として扱う。
function _createDocumentState() {
  var content = null;
  var type = 'mmd';
  var lang = null;

  return {
    record: function (newContent, newType, newLang) {
      content = newContent;
      type = newType;
      lang = newLang;
    },
    // 追記チャンクを直近内容の末尾に足す。まだ何も描画していない間は何もしない。
    append: function (text) {
      if (content !== null) {
        content += text;
      }
    },
    content: function () {
      return content;
    },
    type: function () {
      return type;
    },
    lang: function () {
      return lang;
    },
    hasContent: function () {
      return content !== null;
    },
  };
}

var _mmdDocument = _createDocumentState();

// チャンク境界の持ち越し。render()(初回チャンク)と appendChunk()(追記)が
// record() で更新し、次の appendChunk() だけが endedWithNewline() で読む。
// 強制分割で改行なしに切れたチャンクの続きを、前の行に連結すべきかの判定に使う。
var _mmdChunkTail = (function () {
  var endedWithNewline = true;
  return {
    record: function (text) {
      endedWithNewline = text.length > 0 && text[text.length - 1] === '\n';
    },
    endedWithNewline: function () {
      return endedWithNewline;
    },
  };
})();

export { _mmdDocument, _mmdChunkTail };
