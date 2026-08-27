// 直近に描画した内容・描いた形・チャンク境界・CSV の列書式を保持する。

import type { CsvColumnFormat } from './csv-columns.js';

// 直近に描画した内容(カラースキーム変更時の再描画と、追記チャンクへ渡す前方文脈の
// 取得元)と、実際に描いた形。書き手は render() の record() / recordShape() と
// appendChunk() の append() だけで、読み手は必ずアクセサ経由になる。
// type は mermaid のパースエラー表示でも読むため、初回描画前は mmd(既定の表示型)
// として扱う。
function _createDocumentState() {
  var content: string | null = null;
  var type = 'mmd';
  var lang: string | undefined;
  // 直前の render() が実際に描いた形(renderShape の戻り値、または差分なら 'diff')。
  //
  // 読み手は「同じ文書をどう描いたか」に依存する処理すべて。いまのところ
  // appendChunk(追記戦略)と jump-providers(見出しをどこから列挙するか)の 2 つ。
  // どちらも**この記録だけを見る**こと。表示モードや type から推し直すと、
  // render 側と別々に判定が育って食い違う(TASK-414)。DOM の形
  // (table.code-table や pre code.csv-source)を探す判定も使わない。同じ形は
  // markdown-it が html:true で通したユーザーコンテンツにも現れ(TASK-339)、
  // 差分テーブルも table.code-table を名乗る(TASK-318)。
  //
  // 型を RenderShape の union にしないのは、未知の種別名が届いたときにそのまま
  // 返って render() の else 節(Markdown 描画)へ落ちる経路が実在し、union で
  // 閉じるとその経路が型の上から消えるため。
  var shape = '';

  return {
    record: function (newContent: string, newType: string, newLang: string | undefined): void {
      content = newContent;
      type = newType;
      lang = newLang;
    },
    // 描いた形を記録する。書き手は render() だけ(分岐へ入る前の仮置きと、
    // 差分を組み上げた場合の上書きの 2 回)。ここを他所から書くと、上の
    // 「推し直さない」という約束が崩れる。
    recordShape: function (newShape: string): void {
      shape = newShape;
    },
    shape: function (): string {
      return shape;
    },
    // 追記チャンクを直近内容の末尾に足す。まだ何も描画していない間は何もしない。
    append: function (text: string): void {
      if (content !== null) {
        content += text;
      }
    },
    content: function (): string | null {
      return content;
    },
    type: function (): string {
      return type;
    },
    lang: function (): string | undefined {
      return lang;
    },
    hasContent: function (): boolean {
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
    record: function (text: string): void {
      endedWithNewline = text.length > 0 && text.at(-1) === '\n';
    },
    endedWithNewline: function (): boolean {
      return endedWithNewline;
    },
  };
})();

// CSV/TSV テーブル表示の列ごとの書式判定(csv-columns.js)。初回描画で確定させ、
// チャンク追記(appendChunk)が同じ書式を使うために持ち越す。列全体を見てからでは
// 追記に間に合わないため、先頭チャンクの判定をそのまま再利用する。
//
// 書き手は render() だけ。分岐へ入る前に reset() し、CSV を描いたときだけ
// record() で入れ直す。これは recordShape と同じ約束で、どの経路を通っても
// 記録が確定するようにするため(CSV → 非 CSV → 追記や、別の CSV への切り替えで
// 前の文書の判定が残らない)。DOM(<th> のクラス等)から読み直す形は使わない。
var _mmdCsvColumns = (function () {
  var formats: CsvColumnFormat[] = [];
  return {
    record: function (newFormats: CsvColumnFormat[]): void {
      formats = newFormats;
    },
    reset: function (): void {
      formats = [];
    },
    formats: function (): CsvColumnFormat[] {
      return formats;
    },
  };
})();

export { _mmdDocument, _mmdChunkTail, _mmdCsvColumns };
