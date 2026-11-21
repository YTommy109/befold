// レンダリング差分(TASK-483)の共通部分。CSV のレコードと Markdown のブロックは
// どちらも「ソース行をまとめた単位」で、差分の行をその単位へ引き当てて並べる。
//
// 差分は -U1000000 の全文差分で届く(GitDiffReader.wholeFileContextLines)ため、
// 差分本文だけから旧版・新版の全文を復元できる。チャンク読み込み中の content には
// 頼らず、表示は常に差分から組む(段階読み込み中でも全体がそろう)。

import { parseUnifiedDiff } from './diff-parse.js';
import type { DiffLine } from './diff-parse.js';

/// 表示に並べる 1 単位。side は旧版・新版のどちらの単位か。
interface DiffUnit {
  type: 'context' | 'add' | 'del';
  side: 'old' | 'new';
  index: number;
  block: number | null;
}

// 全文差分から差分行と旧版・新版の全文を取り出す。描けない差分(本文なし・バイナリ・
// 複数ファイル・全文でない差分)では null を返し、呼び出し側が通常表示へ落とす。
function wholeFileDiffSides(
  diffText: string,
): { lines: DiffLine[]; oldText: string; newText: string } | null {
  var files = parseUnifiedDiff(diffText);
  if (files.length !== 1 || files[0]!.isBinary || files[0]!.hunks.length !== 1) {
    return null;
  }
  var hunk = files[0]!.hunks[0]!;
  // 全文差分なら旧版・新版とも 1 行目(新規・削除ファイルは 0)から始まる。
  if (hunk.oldStart > 1 || hunk.newStart > 1) {
    return null;
  }
  var lines = hunk.lines;
  var side = (skip: DiffLine['type']): string =>
    lines
      .filter((l) => l.type !== skip)
      .map((l) => l.text)
      .join('\n');
  return { lines: lines, oldText: side('add'), newText: side('del') };
}

// 行番号(0 始まり)→ 単位番号の表。どの単位にも属さない行(Markdown の空行など)は -1。
function lineToUnit(ranges: [number, number][]): number[] {
  var map: number[] = [];
  for (var r = 0; r < ranges.length; r++) {
    while (map.length < ranges[r]![0]) map.push(-1);
    for (var line = ranges[r]![0]; line < ranges[r]![1]; line++) {
      map[line] = r;
    }
  }
  return map;
}

// 差分の行を文書順に辿り、表示に並べる単位の列を作る。純関数(テストが直接呼ぶ)。
//
// 反対側に同じ文脈行だけを覆う単位が無い単位を、旧側なら削除・新側なら追加とみなす。
// 同じ位置では削除を追加より先に出す(ソース差分の並びと同じ)。未変更の旧単位は
// 新単位と同じものなので出さない。
// 変更ブロックは「削除の連なり + 直後の追加の連なり」を 1 つとして数える
// (assignChangeBlockIndexes と同じ畳み方。差分ジャンプの件数がソース差分と揃う)。
function orderDiffUnits(
  lines: DiffLine[],
  oldRanges: [number, number][],
  newRanges: [number, number][],
): DiffUnit[] {
  var oldOfLine = lineToUnit(oldRanges);
  var newOfLine = lineToUnit(newRanges);
  // 単位ごとに、それが覆う差分行の添字を集める。旧単位が覆うのは文脈行と削除行、
  // 新単位が覆うのは文脈行と追加行。
  var oldCovers: number[][] = oldRanges.map(() => []);
  var newCovers: number[][] = newRanges.map(() => []);
  var oldLine = 0;
  var newLine = 0;
  lines.forEach(function (line, i) {
    if (line.type !== 'add') {
      var o = oldOfLine[oldLine++] ?? -1;
      if (o >= 0) oldCovers[o]!.push(i);
    }
    if (line.type !== 'del') {
      var n = newOfLine[newLine++] ?? -1;
      if (n >= 0) newCovers[n]!.push(i);
    }
  });
  // 単位が未変更なのは、反対側にまったく同じ差分行(= 同じ文脈行だけ)を覆う単位が
  // あるときに限る。削除行・追加行を含めば添字の列は一致しない。行の削除だけ・追加だけの
  // 変更(リストの 1 項目を足す等)や、空行の追加で段落が割れる変更も、単位の境界が
  // 変わるので両側とも変更として扱われる(片側だけ色が付く形にならない)。
  var oldKeys = new Set(oldCovers.map((c) => c.join(',')));
  var newKeys = new Set(newCovers.map((c) => c.join(',')));
  var oldChanged = oldCovers.map((c) => !newKeys.has(c.join(',')));
  var newChanged = newCovers.map((c) => !oldKeys.has(c.join(',')));

  var units: DiffUnit[] = [];
  var oldSeen = -1;
  var newSeen = -1;
  var block = -1;
  var previous: DiffUnit['type'] = 'context';
  function emit(type: DiffUnit['type'], side: 'old' | 'new', index: number): void {
    if (type !== 'context' && (previous === 'context' || (previous === 'add' && type === 'del'))) {
      block++;
    }
    units.push({ type: type, side: side, index: index, block: type === 'context' ? null : block });
    previous = type;
  }
  oldLine = 0;
  newLine = 0;
  lines.forEach(function (line) {
    if (line.type !== 'add') {
      var o = oldOfLine[oldLine++] ?? -1;
      if (o > oldSeen) {
        oldSeen = o;
        if (oldChanged[o]) emit('del', 'old', o);
      }
    }
    if (line.type !== 'del') {
      var n = newOfLine[newLine++] ?? -1;
      if (n > newSeen) {
        newSeen = n;
        emit(newChanged[n] ? 'add' : 'context', 'new', n);
      }
    }
  });
  return units;
}

export type { DiffUnit };
export { wholeFileDiffSides, orderDiffUnits };
