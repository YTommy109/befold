// Help > キーボードショートカット に載せるビューア内のキー操作(Swift 側の
// ViewerShortcutCatalog)が、実際の割り当て(viewer-src/keyboard.ts)と一致すること。
//
// 割り当ての実体は JS、一覧は Swift にあり、どちらからも相手を実行できない。
// そこで Swift の宣言をここでパースして JS の純粋関数へ通す(TASK-503 / TASK-485.10)。
// 配布サイトが MainMenuBuilder*.swift を読んでページ記載のずれを検出しているのと
// 同じ手口。パース結果が 0 件なら失敗させる —— 空集合に対する検証は必ず通るため、
// リテラル形式を変えてパーサが空振りしたときに黙って緑になるのを防ぐ。

const fs = require('fs');
const path = require('path');

const {
  resolveScrollKey,
  resolveBarCloseKey,
  resolveJumpNavigationKey,
} = require('../../../viewer-src/main.js');

const CATALOG_PATH = path.join(__dirname, '../../../befold/App/ViewerShortcutCatalog.swift');

// Swift 側 ViewerShortcutCatalogTests の期待値と同じ値。片方だけ増やすと落ちる。
const EXPECTED_SCROLL_COUNT = 6;
const EXPECTED_FIND_ONLY_COUNT = 1;
const EXPECTED_JUMP_COUNT = 3;

// resolveScrollKey の戻り値。バーの開閉・ジャンプは別の関数で判定する。
const SCROLL_EXPECTATIONS = {
  pageDown: { down: true, amount: 'page' },
  pageUp: { down: false, amount: 'page' },
  lineDown: { down: true, amount: 'line' },
  lineUp: { down: false, amount: 'line' },
  halfPageDown: { down: true, amount: 'half' },
  halfPageUp: { down: false, amount: 'half' },
};

// 素の Enter / Shift+Enter を表す keydown 相当のオブジェクト。
function jumpEvent(key, shift) {
  return {
    key,
    shiftKey: shift,
    metaKey: false,
    ctrlKey: false,
    altKey: false,
    isComposing: false,
    keyCode: 0,
  };
}

// 名前付きの配列リテラル 1 つ分を切り出してから Item を拾う。配列ごとに分けるのは、
// ゲート閉(findOnlyItems)とゲート開(documentJumpItems)で Esc の行が入れ替わるため。
// 全体を 1 回でなめると、どちらの構成に属する行かが分からなくなる。
function parseCatalogArray(source, name) {
  const arrayPattern = new RegExp(
    `static let ${name}: \\[Item\\] = \\[([\\s\\S]*?)\\n {4}\\]`,
    'u',
  );
  const arrayMatch = arrayPattern.exec(source);
  if (arrayMatch === null) return null;

  // 空白と改行を跨げる形にしてある。swiftformat は 1 行が長い宣言を引数ごとに
  // 折り返すため、1 行前提の正規表現だと整形が入った瞬間に取りこぼす
  // (実測: 7 件のうち 1 件が折り返されて 6 件になった)。
  const pattern =
    /Item\(\s*jsKeys:\s*\[([^\]]*)\],\s*shift:\s*(true|false),\s*expects:\s*\.(\w+),\s*titleKey:\s*"([^"]+)"\s*,?\s*\)/gu;
  const items = [];
  let match;
  while ((match = pattern.exec(arrayMatch[1])) !== null) {
    const jsKeys = match[1]
      .split(',')
      .map((raw) => raw.trim())
      .filter((raw) => raw.length > 0)
      .map((raw) => JSON.parse(raw));
    items.push({ jsKeys, shift: match[2] === 'true', expects: match[3], titleKey: match[4] });
  }
  return items;
}

const source = fs.readFileSync(CATALOG_PATH, 'utf8');
const scrollItems = parseCatalogArray(source, 'scrollItems');
const findOnlyItems = parseCatalogArray(source, 'findOnlyItems');
const jumpItems = parseCatalogArray(source, 'documentJumpItems');

describe('ViewerShortcutCatalog と viewer-src/keyboard.ts', () => {
  test('Swift 側のカタログをパースできる（0 件は失敗）', () => {
    expect({
      scroll: scrollItems === null ? null : scrollItems.length,
      findOnly: findOnlyItems === null ? null : findOnlyItems.length,
      jump: jumpItems === null ? null : jumpItems.length,
    }).toEqual({
      scroll: EXPECTED_SCROLL_COUNT,
      findOnly: EXPECTED_FIND_ONLY_COUNT,
      jump: EXPECTED_JUMP_COUNT,
    });
  });

  // 期待値の種類ごとにテストを分ける。1 つのループで分岐して expect を呼ぶと
  // 条件付きアサート(jest/no-conditional-expect)になり、条件を満たす行が 0 件でも
  // 素通りしてしまう。
  test('スクロールのキーは宣言どおりの量・向きへ解決される', () => {
    // 失敗時にどの行かが分かるよう、キーを添えた形で比較する
    // (jest の expect は vitest と違いメッセージ引数を取らない)。
    const actual = scrollItems.flatMap((item) =>
      item.jsKeys.map(
        (key) =>
          `${key} shift=${item.shift} -> ${JSON.stringify(resolveScrollKey(key, item.shift))}`,
      ),
    );
    const expected = scrollItems.flatMap((item) =>
      item.jsKeys.map(
        (key) =>
          `${key} shift=${item.shift} -> ${JSON.stringify(SCROLL_EXPECTATIONS[item.expects])}`,
      ),
    );
    expect(actual).toEqual(expected);
  });

  test('ゲート閉の Esc は検索バーを閉じる操作へ解決される', () => {
    const closed = findOnlyItems.filter((item) => item.expects === 'findClose');
    expect(closed.length).toBe(EXPECTED_FIND_ONLY_COUNT);

    expect(
      closed.flatMap((item) =>
        item.jsKeys.map((key) => `${key} -> ${resolveBarCloseKey(key, 'find', false, 0)}`),
      ),
    ).toEqual(closed.flatMap((item) => item.jsKeys.map((key) => `${key} -> true`)));
  });

  test('ゲート開の Esc は検索バーとジャンプバーのどちらも閉じる', () => {
    const both = jumpItems.filter((item) => item.expects === 'barClose');
    expect(both.length).toBe(1);

    expect(
      both.flatMap((item) =>
        item.jsKeys.flatMap((key) =>
          ['find', 'jump'].map(
            (bar) => `${key} ${bar} -> ${resolveBarCloseKey(key, bar, false, 0)}`,
          ),
        ),
      ),
    ).toEqual(
      both.flatMap((item) =>
        item.jsKeys.flatMap((key) => ['find', 'jump'].map((bar) => `${key} ${bar} -> true`)),
      ),
    );
  });

  test('ジャンプのキーは宣言どおりの向きへ解決される', () => {
    const moves = jumpItems.filter((item) => item.expects !== 'barClose');
    expect(moves.length).toBe(EXPECTED_JUMP_COUNT - 1);

    const actual = moves.flatMap((item) =>
      item.jsKeys.map(
        (key) =>
          `${key} shift=${item.shift} -> ${resolveJumpNavigationKey(jumpEvent(key, item.shift), 'jump')}`,
      ),
    );
    const expected = moves.flatMap((item) =>
      item.jsKeys.map(
        (key) => `${key} shift=${item.shift} -> ${item.expects === 'jumpNext' ? 'next' : 'prev'}`,
      ),
    );
    expect(actual).toEqual(expected);
  });

  test('期待値の語彙はすべて既知のものである', () => {
    const known = new Set([
      ...Object.keys(SCROLL_EXPECTATIONS),
      'findClose',
      'barClose',
      'jumpNext',
      'jumpPrev',
    ]);
    const all = [...scrollItems, ...findOnlyItems, ...jumpItems];
    expect(all.map((item) => item.expects).filter((name) => !known.has(name))).toEqual([]);
  });

  const CANDIDATE_KEYS = [
    ' ',
    'ArrowUp',
    'ArrowDown',
    'ArrowLeft',
    'ArrowRight',
    'Backspace',
    'Enter',
    'Escape',
    'Home',
    'End',
    'PageUp',
    'PageDown',
    ...'abcdefghijklmnopqrstuvwxyz',
  ];

  test('スクロールに反応するキーはすべてカタログに載っている', () => {
    const listed = new Set(
      scrollItems.flatMap((item) => item.jsKeys.map((key) => `${key} ${item.shift}`)),
    );

    for (const key of CANDIDATE_KEYS) {
      for (const shift of [false, true]) {
        if (resolveScrollKey(key, shift) === null) continue;
        expect({ key, shift, listed: listed.has(`${key} ${shift}`) }).toEqual({
          key,
          shift,
          listed: true,
        });
      }
    }
  });

  test('ジャンプ移動に反応するキーはすべてカタログに載っている', () => {
    const listed = new Set(
      jumpItems.flatMap((item) => item.jsKeys.map((key) => `${key} ${item.shift}`)),
    );

    for (const key of CANDIDATE_KEYS) {
      for (const shift of [false, true]) {
        if (resolveJumpNavigationKey(jumpEvent(key, shift), 'jump') === null) continue;
        expect({ key, shift, listed: listed.has(`${key} ${shift}`) }).toEqual({
          key,
          shift,
          listed: true,
        });
      }
    }
  });

  test('バーを閉じる Esc は IME 変換中には効かない', () => {
    // カタログに載せた findClose / barClose の条件を、閉じない側からも押さえる。
    expect(resolveBarCloseKey('Escape', null, false, 0)).toBe(false);
    expect(resolveBarCloseKey('Escape', 'find', true, 0)).toBe(false);
    expect(resolveBarCloseKey('Escape', 'find', false, 229)).toBe(false);
    expect(resolveBarCloseKey('Escape', 'jump', true, 0)).toBe(false);
    expect(resolveBarCloseKey('Escape', 'jump', false, 229)).toBe(false);
  });

  test('ジャンプの Enter はバーが開いていない/IME 変換中/修飾キー付きでは動かない', () => {
    expect(resolveJumpNavigationKey(jumpEvent('Enter', false), null)).toBe(null);
    expect(resolveJumpNavigationKey(jumpEvent('Enter', false), 'find')).toBe(null);
    expect(
      resolveJumpNavigationKey({ ...jumpEvent('Enter', false), isComposing: true }, 'jump'),
    ).toBe(null);
    expect(resolveJumpNavigationKey({ ...jumpEvent('Enter', false), keyCode: 229 }, 'jump')).toBe(
      null,
    );
    expect(resolveJumpNavigationKey({ ...jumpEvent('Enter', false), metaKey: true }, 'jump')).toBe(
      null,
    );
  });
});
