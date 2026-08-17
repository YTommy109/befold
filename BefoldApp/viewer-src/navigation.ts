// 文書内を「文書順に並んだ目印の列」として前後移動するための共有部品。
// 検索バー（find.ts）と文書内ジャンプ（TASK-485）はどちらも
// 「列 + 現在位置 + n/N 表示 + 前後移動」という同じ形をしており、
// 違うのは列の作り方だけ。ここには列の作り方を持ち込まず、
// 位置の算術と件数ラベルの組み立てという純粋な部分だけを置く。

// 目印間の移動先インデックス。件数 0 のときはどれも -1(選択なし)を返す。
// 末尾の次は先頭、先頭の前は末尾へ循環する。

function nextMatchIndex(currentIndex: number, count: number): number {
  if (count <= 0) {
    return -1;
  }
  return (currentIndex + 1) % count;
}

function prevMatchIndex(currentIndex: number, count: number): number {
  if (count <= 0) {
    return -1;
  }
  return (currentIndex - 1 + count) % count;
}

// 列を作り直したときに維持する現在位置。件数が減っても範囲外を指さないよう
// クランプする。負値(未選択)は先頭に寄せる。
function keptMatchIndex(previousIndex: number, count: number): number {
  if (count <= 0) {
    return -1;
  }
  return Math.min(Math.max(previousIndex, 0), count - 1);
}

// 「現在位置/件数」の表示文字列。件数 0 のときは 0/0 を返す
// (専用文言を出すと文字幅の違いでバーが伸縮するため)。
// 段階読み込み中(truncated)は、表示済み DOM だけが対象であることを示す
// ラベルを括弧で付す。
//
// この関数は n/N とラベルの組み立てだけを担う。検索バーが持つ
// 「クエリが空」「正規表現として不正」のときに空文字を出す分岐は、
// ジャンプ側に存在しない状態なのでここへは持ち込まず、呼び出し側に残す
// (TASK-485.1 の設計判断。分岐を吸い出すと検索の表示が静かに変わる)。
function formatNavigationCount(
  currentIndex: number,
  count: number,
  truncated: boolean,
  truncatedLabel: string,
): string {
  var current = count === 0 ? 0 : currentIndex + 1;
  var text = current + '/' + count;
  if (truncated) {
    text += ' (' + truncatedLabel + ')';
  }
  return text;
}

export { nextMatchIndex, prevMatchIndex, keptMatchIndex, formatNavigationCount };
