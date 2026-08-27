// CSV/TSV の列単位の書式判定。テーブル表示の右寄せ・桁区切りをどの列へ
// 適用するかだけを決め、HTML の組み立ては csv-html.ts が持つ。
//
// 判定は「当たれば嬉しい」ではなく「外さない」を優先する。befold の配布先の
// ユーザー層は不明で、郵便番号や商品コードに桁区切りが入る誤りは、金額に
// 桁区切りが入らない取りこぼしよりはるかに悪い。逃げ道としてソース表示
// (⌘2 の csv-source)が無加工の原文を見せている。

/// 列に適用する書式。
/// - 'text'    何もしない
/// - 'numeric' 右寄せ + tabular-nums のみ
/// - 'grouped' 右寄せ + tabular-nums + 整数部の桁区切り
type CsvColumnFormat = 'text' | 'numeric' | 'grouped';

/// 'grouped' にしなかった理由。テストが「どの拒否条件で落ちたか」を
/// 突き合わせるために返す。年の列は必ず「4 桁で全セル同じ桁数」にも該当するなど、
/// 拒否条件は単独では分離できない組み合わせがあり、出力(桁区切りの有無)だけでは
/// どの条件が効いたか検証できない。
type CsvColumnReason =
  | 'grouped'
  | 'not-numeric'
  | 'empty'
  | 'no-large-value'
  | 'leading-zero'
  | 'fixed-width'
  | 'year-range'
  | 'row-number'
  | 'header-word';

interface CsvColumnDecision {
  format: CsvColumnFormat;
  reason: CsvColumnReason;
}

// 列判定に使うデータ行の上限。チャンク追記(render.ts の appendChunk)は
// 列全体を見られないため、先頭チャンクのこの範囲で判定を確定させ、後続チャンクは
// その判定を再利用する。後続で前提が崩れても被害は「桁区切りが残る」だけで、
// 値そのものが誤って出ることはない。
var CSV_SAMPLE_ROWS = 200;

// 「全セルが同じ桁数、かつ 4 桁以上」の拒否条件(固定長コード)を有効にする
// 最小サンプル数。行数の少ないファイルでは、金額列がたまたま全部 5 桁である
// ことが普通に起きる(3 行の請求書など)。4 件以下で桁数が揃うのは偶然の側が
// 濃いと見て 5 件を下限にした。実測の裏付けがある値ではない。
var CSV_FIXED_WIDTH_MIN_SAMPLES = 5;

// 桁区切りを入れる下限。これ未満しか無い列は整形が no-op になる。
var CSV_GROUPING_MIN_VALUE = 1000;

// 4 桁整数を「年」とみなす範囲。
var CSV_YEAR_MIN = 1900;
var CSV_YEAR_MAX = 2100;

// 数値としてそのまま読めるセルの形。通貨記号・単位・カンマ区切りは通さない。
// カンマを通さないことが、整形済みの列と欧州式小数(1.234,56)を第 1 段で
// 落とす役割も兼ねている(そのための独立した拒否条件は置かない)。
var CSV_NUMERIC_RE = /^[+-]?\d+(?:\.\d+)?$/u;

// 先頭ゼロ(郵便番号・商品コード・社員番号)。0 の直後に数字が続く形だけを見るので
// 0.5 のような小数は該当しない。
var CSV_LEADING_ZERO_RE = /^[+-]?0\d/u;

// ヘッダー名でコード列と分かるもの。肯定側(price / 金額 等)のマッチは使わない。
// 網羅不能な上、当てにすると誤爆を増やす方向にしか働かないため。
var CSV_HEADER_WORDS_ASCII = ['id', 'code', 'no', 'zip', 'tel', 'phone', 'year'];
var CSV_HEADER_WORDS_CJK = ['番号', 'コード', '郵便', '電話', '年'];

// ヘッダー名を英数トークンへ割る。camelCase の境界にも区切りを入れるため、
// userId は ['user', 'id'] になる。部分一致にしないのは width の id、
// amount の no のような誤爆を避けるため。
function csvHeaderTokens(header: string): string[] {
  var spaced = header.replaceAll(/([a-z0-9])([A-Z])/gu, '$1 $2');
  return spaced
    .toLowerCase()
    .split(/[^a-z0-9]+/u)
    .filter(function (t: string): boolean {
      return t.length > 0;
    });
}

function csvHeaderLooksLikeCode(header: string): boolean {
  var tokens = csvHeaderTokens(header);
  for (var i = 0; i < CSV_HEADER_WORDS_ASCII.length; i++) {
    if (tokens.includes(CSV_HEADER_WORDS_ASCII[i]!)) {
      return true;
    }
  }
  for (var j = 0; j < CSV_HEADER_WORDS_CJK.length; j++) {
    if (header.includes(CSV_HEADER_WORDS_CJK[j]!)) {
      return true;
    }
  }
  return false;
}

// 整数部の桁数(符号と小数部を除く)。
function csvIntegerDigits(sample: string): number {
  var body = sample.replace(/^[+-]/u, '');
  var dot = body.indexOf('.');
  return dot === -1 ? body.length : dot;
}

// 「1 から始まる連番で全ユニーク」= 行番号列。整数のみで、値の集合が
// 1..件数 と一致するかで見る(並び順は問わない)。
function csvLooksLikeRowNumbers(samples: string[]): boolean {
  var seen = new Set<number>();
  for (var i = 0; i < samples.length; i++) {
    var s = samples[i]!;
    if (s.includes('.') || s.startsWith('-')) {
      return false;
    }
    var n = Number(s);
    if (!Number.isInteger(n) || n < 1 || n > samples.length || seen.has(n)) {
      return false;
    }
    seen.add(n);
  }
  return seen.size === samples.length && samples.length > 0;
}

// 1 列分の判定。samples は非空セルのみ(トリム済み)を渡す。
function classifyCsvColumn(header: string, samples: string[]): CsvColumnDecision {
  if (samples.length === 0) {
    return { format: 'text', reason: 'empty' };
  }
  for (var i = 0; i < samples.length; i++) {
    if (!CSV_NUMERIC_RE.test(samples[i]!)) {
      return { format: 'text', reason: 'not-numeric' };
    }
  }
  // ここから第 2 段。第 1 段を満たす列は、拒否されても右寄せまでは効かせる
  // (ID や年でも右寄せは誤読を生まない)。
  var numericOnly: CsvColumnDecision = { format: 'numeric', reason: 'no-large-value' };

  var hasLarge = false;
  var allSameWidth = true;
  var firstWidth = csvIntegerDigits(samples[0]!);
  var allYears = true;
  for (var j = 0; j < samples.length; j++) {
    var s = samples[j]!;
    if (CSV_LEADING_ZERO_RE.test(s)) {
      return { format: 'numeric', reason: 'leading-zero' };
    }
    var width = csvIntegerDigits(s);
    if (width !== firstWidth) {
      allSameWidth = false;
    }
    if (Math.abs(Number(s)) >= CSV_GROUPING_MIN_VALUE) {
      hasLarge = true;
    }
    if (allYears) {
      var n = Number(s);
      var isYear = !s.includes('.') && width === 4 && n >= CSV_YEAR_MIN && n <= CSV_YEAR_MAX;
      if (!isYear) {
        allYears = false;
      }
    }
  }
  if (!hasLarge) {
    return numericOnly;
  }
  if (allYears) {
    return { format: 'numeric', reason: 'year-range' };
  }
  if (csvLooksLikeRowNumbers(samples)) {
    return { format: 'numeric', reason: 'row-number' };
  }
  if (allSameWidth && firstWidth >= 4 && samples.length >= CSV_FIXED_WIDTH_MIN_SAMPLES) {
    return { format: 'numeric', reason: 'fixed-width' };
  }
  if (csvHeaderLooksLikeCode(header)) {
    return { format: 'numeric', reason: 'header-word' };
  }
  return { format: 'grouped', reason: 'grouped' };
}

// テーブル全体(rows[0] がヘッダー)から列ごとの判定を返す。列数は行の最大長。
// テストと判定の検証のため、理由まで含めた配列を返す analyzeCsvColumnDecisions を
// 本体にし、描画側は format だけを取り出した analyzeCsvColumns を使う。
function analyzeCsvColumnDecisions(rows: string[][]): CsvColumnDecision[] {
  var maxCols = 0;
  for (var r = 0; r < rows.length; r++) {
    if (rows[r]!.length > maxCols) {
      maxCols = rows[r]!.length;
    }
  }
  var lastRow = Math.min(rows.length, CSV_SAMPLE_ROWS + 1);
  var decisions: CsvColumnDecision[] = [];
  for (var c = 0; c < maxCols; c++) {
    var samples: string[] = [];
    for (var d = 1; d < lastRow; d++) {
      var cell = rows[d]![c];
      if (cell === undefined) {
        continue;
      }
      var trimmed = cell.trim();
      if (trimmed !== '') {
        samples.push(trimmed);
      }
    }
    var header = rows.length > 0 ? (rows[0]![c] ?? '') : '';
    decisions.push(classifyCsvColumn(header, samples));
  }
  return decisions;
}

function analyzeCsvColumns(rows: string[][]): CsvColumnFormat[] {
  return analyzeCsvColumnDecisions(rows).map(function (d: CsvColumnDecision): CsvColumnFormat {
    return d.format;
  });
}

// 整数部にのみ 3 桁ごとの ',' を入れる。小数部は原文のまま返し(1.50 を 1.5 に
// しない)、丸め・桁数の正規化は一切しない。区切り文字は ',' 固定で、
// Intl.NumberFormat は使わない(表示がロケールで揺れないようにするため)。
function groupCsvNumber(value: string): string {
  if (!CSV_NUMERIC_RE.test(value)) {
    return value;
  }
  var sign = '';
  var body = value;
  if (body.startsWith('+') || body.startsWith('-')) {
    sign = body.slice(0, 1);
    body = body.slice(1);
  }
  var dot = body.indexOf('.');
  var intPart = dot === -1 ? body : body.slice(0, dot);
  var rest = dot === -1 ? '' : body.slice(dot);
  var grouped = '';
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 === 0) {
      grouped += ',';
    }
    grouped += intPart[i]!;
  }
  return sign + grouped + rest;
}

export type { CsvColumnFormat, CsvColumnReason, CsvColumnDecision };
export {
  CSV_SAMPLE_ROWS,
  CSV_FIXED_WIDTH_MIN_SAMPLES,
  csvHeaderTokens,
  csvHeaderLooksLikeCode,
  classifyCsvColumn,
  analyzeCsvColumnDecisions,
  analyzeCsvColumns,
  groupCsvNumber,
};
