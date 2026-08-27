// CSV/TSV の列書式判定（viewer-src/csv-columns.ts）と、その判定がテーブル表示の
// 初回描画とチャンク追記の両方へ同じ形で届くことのテスト（TASK-557.1）。
//
// 判定は「当たれば嬉しい」ではなく「外さない」を優先する設計なので、テストの
// 重心は「桁区切りが入ること」ではなく **入ってはいけない列に入らないこと** に
// ある。拒否条件は単独では分離できない組み合わせがある（年の列は必然的に
// 「全セル 4 桁で同じ桁数」にも該当する）ため、出力の有無ではなく
// classifyCsvColumn が返す reason を突き合わせる。

const fs = require('node:fs');
const path = require('node:path');

const {
  analyzeCsvColumns,
  buildCsvTable,
  classifyCsvColumn,
  csvHeaderLooksLikeCode,
  csvRowsHtml,
  csvSourceInnerHtml,
  groupCsvNumber,
  parseCsv,
} = require('../../../viewer-src/main.js');
const { loadViewerMain } = require('./support/viewerMainHarness');

describe('classifyCsvColumn の第 1 段（右寄せ）', () => {
  test('非空セルがすべて数値なら numeric になる', () => {
    expect(classifyCsvColumn('qty', ['1', '2', '3'])).toEqual({
      format: 'numeric',
      reason: 'no-large-value',
    });
  });

  test('符号付き・小数を含んでも数値として通る', () => {
    expect(classifyCsvColumn('delta', ['-1.5', '+2', '3.25']).format).toBe('numeric');
  });

  test('数値でないセルが 1 つでもあれば text になる', () => {
    expect(classifyCsvColumn('mixed', ['1', 'N/A', '3'])).toEqual({
      format: 'text',
      reason: 'not-numeric',
    });
  });

  test('空セルは判定から外れる（サンプルが空なら text）', () => {
    expect(classifyCsvColumn('blank', [])).toEqual({ format: 'text', reason: 'empty' });
  });

  test('通貨記号や単位が付くセルは数値として扱わない', () => {
    expect(classifyCsvColumn('price', ['$1200', '$3400']).reason).toBe('not-numeric');
    expect(classifyCsvColumn('weight', ['1200kg', '3400kg']).reason).toBe('not-numeric');
  });
});

describe('classifyCsvColumn の第 2 段（桁区切り）', () => {
  test('1,000 以上を含む量の列は grouped になる', () => {
    expect(classifyCsvColumn('amount', ['1200', '35', '480000'])).toEqual({
      format: 'grouped',
      reason: 'grouped',
    });
  });

  // 以下は拒否条件ごとに 1 件ずつ。どれも「右寄せは残るが桁区切りは入らない」。
  test('1,000 以上の値が 1 つも無ければ整形が no-op なので落とす', () => {
    expect(classifyCsvColumn('score', ['12', '340', '999'])).toEqual({
      format: 'numeric',
      reason: 'no-large-value',
    });
  });

  test('先頭ゼロのセルがあれば落とす（郵便番号・商品コード）', () => {
    expect(classifyCsvColumn('col', ['0123456', '9876543'])).toEqual({
      format: 'numeric',
      reason: 'leading-zero',
    });
  });

  test('4 桁整数が全部 1900〜2100 なら年として落とす', () => {
    expect(classifyCsvColumn('col', ['1999', '2011', '2026', '1980', '2100'])).toEqual({
      format: 'numeric',
      reason: 'year-range',
    });
  });

  test('1 から始まる連番で全ユニークなら行番号として落とす', () => {
    // 1..1200 の連番。1,000 以上を含むので「no-large-value」では落ちない。
    const samples = Array.from({ length: 1200 }, (_, i) => String(i + 1));
    expect(classifyCsvColumn('col', samples)).toEqual({
      format: 'numeric',
      reason: 'row-number',
    });
  });

  test('全セルが同じ桁数かつ 4 桁以上なら固定長コードとして落とす', () => {
    expect(classifyCsvColumn('col', ['1234', '5678', '9012', '3456', '7890'])).toEqual({
      format: 'numeric',
      reason: 'fixed-width',
    });
  });

  test('サンプルが 5 件未満なら固定長の条件は効かない（偶然の一致を拾わない）', () => {
    // 同じ 4 桁揃いでも 4 件なら grouped のまま。行数の少ない金額列を守る側に倒す。
    expect(classifyCsvColumn('col', ['1234', '5678', '9012', '3456'])).toEqual({
      format: 'grouped',
      reason: 'grouped',
    });
  });

  test('ヘッダー名が否定語に一致すれば落とす', () => {
    expect(classifyCsvColumn('user_id', ['1001', '20', '399999'])).toEqual({
      format: 'numeric',
      reason: 'header-word',
    });
  });

  test('カンマを含むセルは第 1 段で落ちる（整形済み・欧州式小数）', () => {
    // 独立した拒否条件を置いていないので、ここが実際の防波堤になる。
    expect(classifyCsvColumn('amount', ['1,234', '5,678']).reason).toBe('not-numeric');
    expect(classifyCsvColumn('amount', ['1.234,56', '9.876,54']).reason).toBe('not-numeric');
  });
});

describe('ヘッダー名の否定語マッチ', () => {
  test.each([
    'id',
    'user_id',
    'userId',
    'ZIP',
    'product code',
    'No.',
    'tel',
    'phone',
    'year',
    '社員番号',
    '商品コード',
    '郵便番号',
    '電話',
    '年',
  ])('%s はコード列とみなす', (header) => {
    expect(csvHeaderLooksLikeCode(header)).toBe(true);
  });

  // 部分一致にすると width の id、amount の no を拾ってしまう。
  test.each(['amount', 'width', 'paid', 'income', 'total', '金額', '売上'])(
    '%s はコード列とみなさない',
    (header) => {
      expect(csvHeaderLooksLikeCode(header)).toBe(false);
    },
  );
});

describe('groupCsvNumber は値を書き換えない', () => {
  test('整数部にだけ区切りが入る', () => {
    expect(groupCsvNumber('1234567')).toBe('1,234,567');
  });

  test('小数部は原文のまま（1.50 が 1.5 にならない）', () => {
    expect(groupCsvNumber('1234.50')).toBe('1,234.50');
    expect(groupCsvNumber('1234.500000')).toBe('1,234.500000');
  });

  test('符号は保たれる', () => {
    expect(groupCsvNumber('-1234')).toBe('-1,234');
    expect(groupCsvNumber('+1234')).toBe('+1,234');
  });

  test('3 桁以下はそのまま', () => {
    expect(groupCsvNumber('999')).toBe('999');
  });

  test('数値でない文字列は素通しする', () => {
    expect(groupCsvNumber('1,234')).toBe('1,234');
    expect(groupCsvNumber('abc')).toBe('abc');
  });
});

describe('テーブル HTML への反映', () => {
  test('数値列の th/td に csv-num が付き、量の列にだけ桁区切りが入る', () => {
    const { html, formats } = buildCsvTable(
      ['name,amount,zip', 'a,1200,0012345', 'b,340000,0987654'].join('\n'),
      ',',
    );
    expect(formats).toEqual(['text', 'grouped', 'numeric']);
    expect(html).toContain('<th>name</th>');
    expect(html).toContain('<th class="csv-num">amount</th>');
    expect(html).toContain('<td class="csv-num">1,200</td>');
    expect(html).toContain('<td class="csv-num">340,000</td>');
    // 郵便番号は右寄せまで。桁区切りも先頭ゼロの欠落も起きない。
    expect(html).toContain('<td class="csv-num">0012345</td>');
  });

  test('text 列のセルは従来どおりのマークアップのまま', () => {
    const { html } = buildCsvTable('name,note\na,x\n', ',');
    expect(html).toContain('<td>a</td>');
    expect(html).toContain('<td>x</td>');
  });

  test('小数を含む量の列は小数部が原文のまま出る', () => {
    const { html } = buildCsvTable('name,amount\na,1234.50\nb,12.00\n', ',');
    expect(html).toContain('<td class="csv-num">1,234.50</td>');
    expect(html).toContain('<td class="csv-num">12.00</td>');
  });

  test('セル前後の空白は落とさずに整形する', () => {
    const html = csvRowsHtml([[' 1200 ']], 1, ['grouped']);
    expect(html).toBe('<tr><td class="csv-num"> 1,200 </td></tr>');
  });

  test('判定の無い列（後続チャンクで増えた列）は素通しする', () => {
    expect(csvRowsHtml([['1200', '3400']], 2, ['grouped'])).toBe(
      '<tr><td class="csv-num">1,200</td><td>3400</td></tr>',
    );
  });

  test('ソース表示の出力は変わらない（桁区切りもクラスも入らない）', () => {
    const inner = csvSourceInnerHtml('name,amount\na,1200\n', ',');
    expect(inner).toContain('<span class="csv-col-1">1200</span>');
    expect(inner).not.toContain('csv-num');
    expect(inner).not.toContain('1,200');
  });

  test('style.css が csv-num の右寄せと tabular-nums を持つ', () => {
    // クラスを付けるだけでは桁は揃わない。見た目側の担保はここでしか測れない。
    const css = fs.readFileSync(path.join(__dirname, '..', 'style.css'), 'utf8');
    expect(css).toContain('#diagram-wrap.csv-body table td.csv-num');
    expect(css).toContain('font-variant-numeric: tabular-nums;');
  });
});

describe('analyzeCsvColumns のサンプル範囲', () => {
  test('ヘッダー + 先頭 200 データ行までで判定する', () => {
    // 201 行目以降に非数値を置いても、先頭 200 行の判定は数値のまま確定する。
    const rows = [['amount']];
    for (let i = 0; i < 200; i++) {
      rows.push([String(1200 + i * 500)]);
    }
    rows.push(['N/A']);
    expect(analyzeCsvColumns(rows)).toEqual(['grouped']);
  });

  test('先頭 200 行の中に非数値があれば text になる', () => {
    const rows = [['amount']];
    for (let i = 0; i < 199; i++) {
      rows.push([String(1200 + i * 500)]);
    }
    rows.push(['N/A']);
    expect(analyzeCsvColumns(rows)).toEqual(['text']);
  });
});

// テーブル本文のセルを「文字列 + 数値列として扱われたか」の組で取り出す。
function tableCells(document) {
  return Array.from(document.querySelectorAll('#diagram-wrap tbody td')).map((cell) => ({
    text: cell.textContent,
    numeric: cell.classList.contains('csv-num'),
  }));
}

describe('チャンク追記が初回チャンクの判定を再利用する', () => {
  test('追記された行にも先頭チャンクと同じ列判定が効く', async () => {
    const { document, main } = loadViewerMain({});
    await main.render('name,amount\na,1200\n', 'csv', ',');

    main.appendChunk('b,340000\n', 'csv', ',');

    expect(tableCells(document)).toEqual([
      { text: 'a', numeric: false },
      { text: '1,200', numeric: true },
      { text: 'b', numeric: false },
      { text: '340,000', numeric: true },
    ]);
  });

  test('別の文書を描いたあとの追記に前の文書の判定が残らない', async () => {
    const { document, main } = loadViewerMain({});
    await main.render('name,amount\na,1200\n', 'csv', ',');
    // コード列しか無い CSV へ切り替える。前の判定が残っていれば 2 列目が
    // 0012345 ではなく桁区切り付きで出る。
    await main.render('name,zip\na,0012345\n', 'csv', ',');

    main.appendChunk('b,0987654\n', 'csv', ',');

    expect(tableCells(document)).toEqual([
      { text: 'a', numeric: false },
      { text: '0012345', numeric: true },
      { text: 'b', numeric: false },
      { text: '0987654', numeric: true },
    ]);
  });

  test('parseCsv 経由の生データは書き換わらない（整形は HTML 組み立てだけ）', () => {
    expect(parseCsv('a,1200\n', ',')).toEqual([['a', '1200']]);
  });
});
