// 差分テキストの構造化。unified diff の解析と、行の並べ替え(変更ブロック・左右の対)。

/// 差分行の種別。旧側・新側のどちらに現れるかを決める。
export type DiffLineType = 'context' | 'add' | 'del';

/// unified diff の 1 行。oldNumber / newNumber は片側にしか無い行では null。
export interface DiffLine {
  type: DiffLineType;
  text: string;
  oldNumber: number | null;
  newNumber: number | null;
}

/// unified diff の 1 ハンク。oldStart / newStart は `@@ -a,b +c,d @@` の開始行番号。
export interface DiffHunk {
  oldStart: number;
  newStart: number;
  lines: DiffLine[];
}

/// unified diff の 1 ファイル分。パスはヘッダが無ければ null のまま。
export interface DiffFile {
  oldPath: string | null;
  newPath: string | null;
  isBinary: boolean;
  hunks: DiffHunk[];
}

/// 左右分割で 1 行に並べる旧側 / 新側の対。値は `hunk.lines` の添字で、
/// 対応する行が無い側は null。
export interface DiffLinePair {
  left: number | null;
  right: number | null;
}

// unified diff の 1 ハンクのヘッダー。`@@ -12,7 +12,9 @@ ...` の数値部だけを見る。
var DIFF_HUNK_HEADER = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/u;

// unified diff をファイル → ハンク → 行の構造へ分解する。
// 行の種別は 'context' / 'add' / 'del' の 3 つで、旧側・新側の行番号を各行に付ける
// (描画側で 2 本のガターに出すため。片側にしか無い行はもう一方が null)。
// `\ No newline at end of file` は直前の行に対する注記であり、行としては数えない。
export function parseUnifiedDiff(text: string | null | undefined): DiffFile[] {
  var files: DiffFile[] = [];
  var file: DiffFile | null = null;
  var hunk: DiffHunk | null = null;
  var oldNumber = 0;
  var newNumber = 0;
  var lines = (text ?? '').split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]!;
    if (line.indexOf('diff --git ') === 0) {
      file = { oldPath: null, newPath: null, isBinary: false, hunks: [] };
      files.push(file);
      hunk = null;
      continue;
    }
    if (file === null) {
      continue;
    }
    // ヘッダ類はハンクが始まる前にしか現れない。ハンク内で同じ接頭辞を持つ行は
    // 本文（`-- ` で始まる SQL コメントの削除など）なので、ここで消費しない。
    if (hunk === null) {
      if (line.indexOf('--- ') === 0) {
        file.oldPath = diffPath(line.slice(4));
        continue;
      }
      if (line.indexOf('+++ ') === 0) {
        file.newPath = diffPath(line.slice(4));
        continue;
      }
      if (line.indexOf('Binary files ') === 0 || line.indexOf('GIT binary patch') === 0) {
        file.isBinary = true;
        continue;
      }
    }
    var header = line.match(DIFF_HUNK_HEADER);
    if (header) {
      // ハンクヘッダーの数値部は 10 進固定で読む。Number() + Math.trunc は
      // 先頭 0 や空文字の扱いが変わるうえ、基数を明示しない形になる。
      // oxlint-disable-next-line unicorn/prefer-number-coercion
      oldNumber = parseInt(header[1]!, 10);
      // oxlint-disable-next-line unicorn/prefer-number-coercion
      newNumber = parseInt(header[3]!, 10);
      hunk = { oldStart: oldNumber, newStart: newNumber, lines: [] };
      file.hunks.push(hunk);
      continue;
    }
    if (hunk === null) {
      continue;
    }
    if (line.indexOf('\\') === 0) {
      continue;
    }
    var marker = line.charAt(0);
    var body = line.slice(1);
    if (marker === '+') {
      hunk.lines.push({ type: 'add', text: body, oldNumber: null, newNumber: newNumber });
      newNumber += 1;
    } else if (marker === '-') {
      hunk.lines.push({ type: 'del', text: body, oldNumber: oldNumber, newNumber: null });
      oldNumber += 1;
    } else if (marker === ' ') {
      // 空文字列の行は本文ではない(git は空の文脈行も先頭 1 文字の空白を付けて出す)。
      // 末尾の改行で生じる空要素を文脈行として数えると、以降の行番号が 1 つずれる。
      hunk.lines.push({ type: 'context', text: body, oldNumber: oldNumber, newNumber: newNumber });
      oldNumber += 1;
      newNumber += 1;
    }
  }
  return files;
}

// `a/path/to/file.swift` の接頭辞を落とす。`/dev/null` はそのまま返す(新規・削除の印)。
function diffPath(raw: string): string {
  var path = raw.split('\t')[0]!;
  if (path === '/dev/null') {
    return path;
  }
  return path.replace(/^[ab]\//u, '');
}

// 連続する変更行を 1 つの「変更ブロック」へまとめ、行ごとのブロック番号を返す。
// 番号は文書順の通し番号で、`startIndex` から始める(ファイル・ハンクをまたいで
// 続けるため、呼び出し側が次の開始値を持ち回る)。文脈行は null。
//
// 削除の連なりと、その直後に続く追加の連なりは 1 ブロックとして数える
// (左右分割が `pairDiffLines` で同じ畳み方をしており、そこと数え方を変えると
// 同じ差分がレイアウトによって違う件数になる)。ハンクの境目をまたいでは
// 続けない: 呼び出し側がハンクごとに呼ぶため、境目で必ず切れる。
//
// **ハンク単位では数えられない。** GitDiffReader は -U1000000 を使うため
// ファイル全体が 1 ハンクになりうる(BefoldKit/GitDiffReader.swift:101)。
export function assignChangeBlockIndexes(lines: DiffLine[], startIndex: number): (number | null)[] {
  var result: (number | null)[] = [];
  var next = startIndex;
  var i = 0;
  while (i < lines.length) {
    if (lines[i]!.type === 'context') {
      result.push(null);
      i += 1;
      continue;
    }
    var block = next;
    next += 1;
    while (i < lines.length && lines[i]!.type === 'del') {
      result.push(block);
      i += 1;
    }
    while (i < lines.length && lines[i]!.type === 'add') {
      result.push(block);
      i += 1;
    }
  }
  return result;
}

// 次のハンクへ持ち越す通し番号。ブロックを 1 つも含まないハンク(文脈行だけ)でも
// 正しく据え置くため、割り当て結果から最大値を読む(呼び出し側が数え直さない)。
export function nextChangeBlockIndex(blocks: (number | null)[], startIndex: number): number {
  var next = startIndex;
  for (var i = 0; i < blocks.length; i++) {
    var block = blocks[i];
    if (block !== null && block !== undefined && block + 1 > next) {
      next = block + 1;
    }
  }
  return next;
}

// 左右分割表示のために、ハンクの行を「旧側 / 新側」の対へ畳む。
// 連続する削除と追加は同じ行に並べる(エディタの差分表示と同じ見え方)。
// 返すのは行オブジェクトではなく `hunk.lines` の添字。ハイライト済み HTML を
// 添字で引くため(ハンク単位でまとめてハイライトする方針を崩さない)。
export function pairDiffLines(lines: DiffLine[]): DiffLinePair[] {
  var pairs: DiffLinePair[] = [];
  var i = 0;
  while (i < lines.length) {
    if (lines[i]!.type === 'context') {
      pairs.push({ left: i, right: i });
      i += 1;
      continue;
    }
    var dels: number[] = [];
    var adds: number[] = [];
    while (i < lines.length && lines[i]!.type === 'del') {
      dels.push(i);
      i += 1;
    }
    while (i < lines.length && lines[i]!.type === 'add') {
      adds.push(i);
      i += 1;
    }
    var count = Math.max(dels.length, adds.length);
    for (var k = 0; k < count; k++) {
      pairs.push({
        left: k < dels.length ? dels[k]! : null,
        right: k < adds.length ? adds[k]! : null,
      });
    }
  }
  return pairs;
}
