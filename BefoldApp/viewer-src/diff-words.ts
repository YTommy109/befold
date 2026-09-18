// 変更行の中で実際に変わった語だけを求め、ハイライト済みの行 HTML へ重ねる。
// DOM には触らず文字列だけを扱う(表への載せ方は diff-html.ts が持つ)。
//
// 計算を Swift ではなくここで行う理由は TASK-528 の Implementation Notes を参照。
// 要点だけ書くと、ブリッジは生の unified diff 文字列を渡す契約で
// (BefoldKit/ViewerDiffBridge.swift)、構造化データへ変えると BefoldRenderKit 経由で
// QuickLook 拡張まで波及する一方、語差分は行テキストだけで完結するため。

/// 行テキスト上の強調範囲。`end` は含まない(String.slice と同じ半開区間)。
interface WordRange {
  start: number;
  end: number;
}

/// 変更行の対に対する強調範囲。旧側・新側で別々の位置になる。
interface WordDiffRanges {
  old: WordRange[];
  new: WordRange[];
}

// 語強調の開始・終了タグ。
var WORD_OPEN = '<span class="diff-word">';
var WORD_CLOSE = '</span>';

// 行 HTML を「タグ / 実体参照 / 生テキスト」へ切り分ける。実体参照(`&lt;` `&#x27;` など)は
// 復号すると 1 文字なので、位置を数えるときに 1 つの単位として扱う必要がある。
// 最後の `[<&]` は、実体参照にならない裸の `&` を生テキスト 1 文字として拾うための受け皿。
var HTML_TOKEN = /<[^>]*>|&[#0-9A-Za-z]+;|[^<&]+|[<&]/gu;

// 語分割器。Intl.Segmenter は ICU の辞書分割を使うので、空白で区切られない日本語の
// 行でも語に割れる(実測: 「これは日本語の文です。」→ これ|は|日本語|の|文|です|。)。
// macOS 14+ の WebKit と Node 24 のどちらにもあるが、無い環境では語差分を出さず
// 従来の行単位の色分けへ落とす。生成コストがあるのでモジュールで 1 つだけ持つ。
var WORD_SEGMENTER: Intl.Segmenter | null =
  typeof Intl !== 'undefined' && typeof Intl.Segmenter === 'function'
    ? new Intl.Segmenter(undefined, { granularity: 'word' })
    : null;

// 行を語の並びへ分割する。語だけでなく空白・記号も要素として残す
// (連結すると元の行に戻る = 要素の長さをそのまま文字位置に使える)。
function segmentWords(text: string): string[] {
  return Array.from(WORD_SEGMENTER!.segment(text), function (segment) {
    return segment.segment;
  });
}

// 先頭から一致する語数。
function commonPrefixCount(a: string[], b: string[]): number {
  var limit = Math.min(a.length, b.length);
  var i = 0;
  while (i < limit && a[i] === b[i]) {
    i += 1;
  }
  return i;
}

// 末尾から一致する語数。`head` より手前までは戻らない(前後の一致が重ならないようにする)。
function commonSuffixCount(a: string[], b: string[], head: number): number {
  var limit = Math.min(a.length, b.length) - head;
  var i = 0;
  while (i < limit && a[a.length - 1 - i] === b[b.length - 1 - i]) {
    i += 1;
  }
  return i;
}

// 語の添字区間 [from, to) を文字位置の範囲へ直す。空区間では範囲を作らない
// (片側だけの挿入・削除では、もう一方に強調すべき文字が無い)。
function wordSpan(words: string[], from: number, to: number): WordRange[] {
  if (from >= to) {
    return [];
  }
  var start = 0;
  for (var i = 0; i < from; i++) {
    start += words[i]!.length;
  }
  var end = start;
  for (var k = from; k < to; k++) {
    end += words[k]!.length;
  }
  return [{ start: start, end: end }];
}

// 範囲が行全体を覆っているか。空行は「覆っている」とみなす(強調しても何も見えない)。
function coversWholeLine(ranges: WordRange[], text: string): boolean {
  if (ranges.length === 0) {
    return text.length === 0;
  }
  return ranges[0]!.start === 0 && ranges[0]!.end >= text.length;
}

// 変更行の対から、旧側・新側それぞれの強調範囲を求める。
// 語の並びの共通接頭辞・共通接尾辞を落とし、残った中間だけを強調する。
// ponytail: 中間は 1 つの連続範囲にまとめる。行内に離れた変更が 2 箇所あると
// その間の共通部分まで強調に含まれる(強調は必ず実際の変更を含む上位集合になる)。
// 語単位の LCS へ上げるのは、実際に読みづらい例が出てからでよい。
//
// 次のときは null を返し、呼び出し側は従来どおり行全体の色分けだけを出す。
// - Intl.Segmenter が無い(語に割る根拠が無い)
// - 両側とも行全体が強調になる(見た目が行単位の色分けと同じになり、情報が増えない)
function wordDiffRanges(oldText: string, newText: string): WordDiffRanges | null {
  if (WORD_SEGMENTER === null) {
    return null;
  }
  var oldWords = segmentWords(oldText);
  var newWords = segmentWords(newText);
  var head = commonPrefixCount(oldWords, newWords);
  var tail = commonSuffixCount(oldWords, newWords, head);
  var oldRanges = wordSpan(oldWords, head, oldWords.length - tail);
  var newRanges = wordSpan(newWords, head, newWords.length - tail);
  if (coversWholeLine(oldRanges, oldText) && coversWholeLine(newRanges, newText)) {
    return null;
  }
  return { old: oldRanges, new: newRanges };
}

// 文字位置 `at` を含む範囲。無ければ null。
function rangeAt(at: number, ranges: WordRange[]): WordRange | null {
  for (var i = 0; i < ranges.length; i++) {
    if (at >= ranges[i]!.start && at < ranges[i]!.end) {
      return ranges[i]!;
    }
  }
  return null;
}

// `at` 以降で最初に始まる範囲の開始位置。無ければ null。
function nextRangeStart(at: number, ranges: WordRange[]): number | null {
  var best: number | null = null;
  for (var i = 0; i < ranges.length; i++) {
    var start = ranges[i]!.start;
    if (start > at && (best === null || start < best)) {
      best = start;
    }
  }
  return best;
}

// 生テキスト 1 片(エスケープ済み、実体参照を含まない)を範囲の境目で切り、
// 強調部分だけを包む。片の中で閉じるので、タグ境界をまたぐ span は生まれない。
function markTextRun(run: string, start: number, ranges: WordRange[]): string {
  var out = '';
  var i = 0;
  while (i < run.length) {
    var at = start + i;
    var range = rangeAt(at, ranges);
    if (range === null) {
      var next = nextRangeStart(at, ranges);
      var plainEnd = next === null ? run.length : Math.min(run.length, next - start);
      out += run.slice(i, plainEnd);
      i = plainEnd;
      continue;
    }
    var markedEnd = Math.min(run.length, range.end - start);
    out += WORD_OPEN + run.slice(i, markedEnd) + WORD_CLOSE;
    i = markedEnd;
  }
  return out;
}

// ハイライト済みの 1 行 HTML に語強調を重ねる。
//
// 包むのはテキストの実行部だけで、hljs が出した <span> は 1 つも分割しない。
// そのため入れ子は壊れず、jump-providers.ts が使う hljs-comment / hljs-string の
// 存在判定も、.line-content の textContent も変わらない。
//
// 位置合わせは「行 HTML を復号した文字列 == line.text」という前提に乗っている。
// 前提が崩れた行(復号後の文字数が合わない)は強調を諦めて元の HTML を返す。
// 崩れたまま包むと、無関係な位置が強調される形で静かに間違うため。
function markWordRanges(lineHtml: string, text: string, ranges: WordRange[] | null): string {
  if (ranges === null || ranges.length === 0) {
    return lineHtml;
  }
  var out = '';
  var decoded = 0;
  HTML_TOKEN.lastIndex = 0;
  var token: RegExpExecArray | null;
  while ((token = HTML_TOKEN.exec(lineHtml)) !== null) {
    var raw = token[0];
    if (raw.length > 1 && raw.charAt(0) === '<') {
      out += raw;
      continue;
    }
    if (raw.length > 1 && raw.charAt(0) === '&') {
      // 実体参照は復号すると 1 文字。切らずに丸ごと包むか、そのまま出すかのどちらか。
      out += rangeAt(decoded, ranges) === null ? raw : WORD_OPEN + raw + WORD_CLOSE;
      decoded += 1;
      continue;
    }
    out += markTextRun(raw, decoded, ranges);
    decoded += raw.length;
  }
  if (decoded !== text.length) {
    return lineHtml;
  }
  return out;
}

export { markWordRanges, segmentWords, wordDiffRanges };
export type { WordDiffRanges, WordRange };
