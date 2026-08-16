// Help > キーボードショートカット に載せるビューア内のキー操作(Swift 側の
// ViewerShortcutCatalog)が、実際の割り当て(viewer-src/keyboard.js)と一致すること。
//
// 割り当ての実体は JS、一覧は Swift にあり、どちらからも相手を実行できない。
// そこで Swift の宣言をここでパースして JS の純粋関数へ通す(TASK-503)。
// 配布サイトが MainMenuBuilder*.swift を読んでページ記載のずれを検出しているのと
// 同じ手口。パース結果が 0 件なら失敗させる —— 空集合に対する検証は必ず通るため、
// リテラル形式を変えてパーサが空振りしたときに黙って緑になるのを防ぐ。

const fs = require('fs');
const path = require('path');

const { resolveScrollKey, resolveFindCloseKey } = require('../../../viewer-src/main.js');

const CATALOG_PATH = path.join(__dirname, '../../../befold/App/ViewerShortcutCatalog.swift');

// Swift 側 ViewerShortcutCatalogTests.expectedItemCount と同じ値。片方だけ増やすと落ちる。
const EXPECTED_VIEWER_SHORTCUT_COUNT = 7;

// resolveScrollKey の戻り値。findClose だけは resolveFindCloseKey で判定する。
const SCROLL_EXPECTATIONS = {
  pageDown: { down: true, amount: 'page' },
  pageUp: { down: false, amount: 'page' },
  lineDown: { down: true, amount: 'line' },
  lineUp: { down: false, amount: 'line' },
  halfPageDown: { down: true, amount: 'half' },
  halfPageUp: { down: false, amount: 'half' },
};

function parseCatalog(source) {
  // 空白と改行を跨げる形にしてある。swiftformat は 1 行が長い宣言を引数ごとに
  // 折り返すため、1 行前提の正規表現だと整形が入った瞬間に取りこぼす
  // (実測: 7 件のうち 1 件が折り返されて 6 件になった)。
  const pattern =
    /Item\(\s*jsKeys:\s*\[([^\]]*)\],\s*shift:\s*(true|false),\s*expects:\s*\.(\w+),\s*titleKey:\s*"([^"]+)"\s*,?\s*\)/g;
  const items = [];
  let match;
  while ((match = pattern.exec(source)) !== null) {
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
const items = parseCatalog(source);

describe('ViewerShortcutCatalog と viewer-src/keyboard.js', () => {
  test('Swift 側のカタログをパースできる（0 件は失敗）', () => {
    expect(items.length).toBe(EXPECTED_VIEWER_SHORTCUT_COUNT);
  });

  // 期待値の種類ごとにテストを分ける。1 つのループで分岐して expect を呼ぶと
  // 条件付きアサート(jest/no-conditional-expect)になり、条件を満たす行が 0 件でも
  // 素通りしてしまう。
  test('スクロールのキーは宣言どおりの量・向きへ解決される', () => {
    const scrollItems = items.filter((item) => item.expects !== 'findClose');
    expect(scrollItems.length).toBe(EXPECTED_VIEWER_SHORTCUT_COUNT - 1);

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

  test('findClose のキーは検索バーを閉じる操作へ解決される', () => {
    const findItems = items.filter((item) => item.expects === 'findClose');
    expect(findItems.length).toBe(1);

    const closed = findItems.flatMap((item) =>
      item.jsKeys.map((key) => `${key} -> ${resolveFindCloseKey(key, true, false, 0)}`),
    );
    expect(closed).toEqual(findItems.flatMap((item) => item.jsKeys.map((key) => `${key} -> true`)));
  });

  test('期待値の語彙はすべて既知のものである', () => {
    const known = new Set([...Object.keys(SCROLL_EXPECTATIONS), 'findClose']);
    expect(items.map((item) => item.expects).filter((name) => !known.has(name))).toEqual([]);
  });

  test('スクロールに反応するキーはすべてカタログに載っている', () => {
    const listed = new Set(
      items.flatMap((item) => item.jsKeys.map((key) => `${key} ${item.shift}`)),
    );
    const candidates = [
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

    for (const key of candidates) {
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

  test('検索バーを閉じる Esc は IME 変換中には効かない', () => {
    // カタログに載せた findClose の条件を、閉じない側からも押さえる。
    expect(resolveFindCloseKey('Escape', false, false, 0)).toBe(false);
    expect(resolveFindCloseKey('Escape', true, true, 0)).toBe(false);
    expect(resolveFindCloseKey('Escape', true, false, 229)).toBe(false);
  });
});
