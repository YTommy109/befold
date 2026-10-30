import { describe, expect, jest, test } from '@jest/globals';

import { loadViewerMain } from './support/viewerMainHarness.js';

function nativeFind(html: string) {
  const loaded = loadViewerMain();
  const { window, document, main } = loaded;
  const frames = new Map<number, FrameRequestCallback>();
  let frameID = 0;
  window.requestAnimationFrame = (callback) => {
    frames.set(++frameID, callback);
    return frameID;
  };
  window.cancelAnimationFrame = (id) => {
    frames.delete(id);
  };
  const flushHighlights = () => {
    const pending = Array.from(frames.values());
    frames.clear();
    pending.forEach((callback) => {
      callback(0);
    });
  };
  window.HTMLElement.prototype.getBoundingClientRect = () => new window.DOMRect(0, 0, 800, 600);
  // CSS.highlights と Highlight はハーネス（installBrowserStubs）が用意する。
  const highlights = window.CSS.highlights as unknown as Map<string, Set<StaticRange>>;
  const wrap = document.getElementById('diagram-wrap')!;
  wrap.innerHTML = html;
  main._mmdOpenFind();
  const input = document.getElementById('mmd-find-input') as HTMLInputElement;
  const query = (value: string) => {
    input.value = value;
    input.dispatchEvent(new window.Event('input'));
  };
  const matches = () => Array.from(highlights.get('mmd-find-match') || []);
  const current = () => Array.from(highlights.get('mmd-find-match-current') || [])[0];
  const count = () => document.getElementById('mmd-find-count')!.textContent;
  return { ...loaded, wrap, highlights, input, query, matches, current, count, flushHighlights };
}

function expectSameRange(actual: StaticRange | undefined, expected: StaticRange | undefined) {
  expect(actual!.startContainer).toBe(expected!.startContainer);
  expect(actual!.startOffset).toBe(expected!.startOffset);
  expect(actual!.endContainer).toBe(expected!.endContainer);
  expect(actual!.endOffset).toBe(expected!.endOffset);
}

describe('native find highlights', () => {
  test('typing and navigation preserve syntax, text nodes, and selection across inline boundaries', () => {
    const { document, window, main, wrap, query, matches, current, count } = nativeFind(
      '<p><span>foo</span><b>.</b><a href="/bar">bar</a> foo.bar</p>',
    );
    const original = wrap.innerHTML;
    const first = wrap.querySelector('span')!.firstChild!;
    const selection = document.getSelection()!;
    selection.setBaseAndExtent(first, 1, first, 2);
    const mutations = new window.MutationObserver(() => {});
    mutations.observe(wrap, { childList: true, subtree: true, characterData: true });

    for (const text of ['f', 'fo', 'foo.', 'foo.bar', 'foo.', 'foo.bar']) query(text);

    expect(count()).toBe('1/2');
    expect(matches()[0]!.startContainer).toBe(first);
    expect(matches()[0]!.endContainer).toBe(wrap.querySelector('a')!.firstChild);
    expectSameRange(current(), matches()[0]);
    main._mmdFind.prev();
    expectSameRange(current(), matches()[1]);
    expect(count()).toBe('2/2');
    main._mmdFind.next();
    expectSameRange(current(), matches()[0]);
    expect(selection.toString()).toBe('o');
    expect(selection.anchorNode).toBe(first);
    expect(wrap.innerHTML).toBe(original);
    expect(mutations.takeRecords()).toEqual([]);
    mutations.disconnect();
    main._mmdCloseFind();
    expect(wrap.innerHTML).toBe(original);
    expect(matches()).toEqual([]);
    expect(current()).toBeUndefined();
  });

  test('search options and cell boundaries retain their existing meaning', () => {
    const { document, query, count, matches, highlights } = nativeFind(
      '<table><tr><td>Foo.bar foo.bar foobar</td><td>foo</td><td>.bar</td></tr></table><svg><text>foo.bar</text></svg>',
    );
    query('foo.bar');
    expect(count()).toBe('1/2');
    document.getElementById('mmd-find-case')!.click();
    expect(count()).toBe('1/1');
    document.getElementById('mmd-find-word')!.click();
    document.getElementById('mmd-find-regex')!.click();
    query('Foo\\.bar');
    expect(count()).toBe('1/1');
    query('[');
    expect(matches()).toEqual([]);
    expect(highlights.has('mmd-find-match-current')).toBe(false);
    expect(count()).toBe('');
    query('(?=foo)');
    expect(count()).toBe('0/0');
  });

  test('large CSV source scopes retain exact endpoints and multiline matches', () => {
    const { document, wrap, query, matches, count } = nativeFind(
      '<code class="csv-source">' + '<span>foo</span>\n'.repeat(2048) + '</code>',
    );
    const spans = wrap.querySelectorAll('span');
    query('foo');
    expect(count()).toBe('1/2048');
    expect(matches()[1024]!.startContainer).toBe(spans[1024]!.firstChild);
    document.getElementById('mmd-find-regex')!.click();
    query('foo\\nfoo');
    expect(count()).toBe('1/1024');
    expect(matches()[0]!.startContainer).toBe(spans[0]!.firstChild);
    expect(matches()[0]!.endContainer).toBe(spans[1]!.firstChild);
    expect(matches()[0]!.endOffset).toBe(3);
  });

  test('empty text nodes at inline boundaries preserve exact match endpoints', () => {
    const { document, wrap, query, matches } = nativeFind('<span>foo</span><b>.</b><a>bar</a>');
    const span = wrap.querySelector('span')!;
    const punctuation = wrap.querySelector('b')!;
    const link = wrap.querySelector('a')!;
    wrap.prepend(document.createTextNode(''));
    span.append(document.createTextNode(''));
    punctuation.prepend(document.createTextNode(''));
    link.append(document.createTextNode(''));
    query('.bar');
    expect(matches()[0]!.startContainer).toBe(punctuation.lastChild);
    expect(matches()[0]!.startOffset).toBe(0);
    expect(matches()[0]!.endContainer).toBe(link.firstChild);
    expect(matches()[0]!.endOffset).toBe(3);
    query('foo.');
    expect(matches()[0]!.startContainer).toBe(span.firstChild);
    expect(matches()[0]!.endContainer).toBe(punctuation.lastChild);
    expect(matches()[0]!.endOffset).toBe(1);
  });

  test('adjacent native matches skip empty nodes without shifting either endpoint', () => {
    const { document, wrap, query, matches } = nativeFind(
      '<code class="csv-source">' + '<span>hit</span>'.repeat(3) + '</code>',
    );
    const nodes = Array.from(wrap.querySelectorAll('span'), (span) => {
      const text = span.firstChild!;
      span.prepend(document.createTextNode(''), document.createTextNode(''));
      span.append(document.createTextNode(''), document.createTextNode(''));
      return text;
    });

    query('hit');

    expect(matches()).toHaveLength(nodes.length);
    matches().forEach((match, index) => {
      expect(match.startContainer).toBe(nodes[index]);
      expect(match.startOffset).toBe(0);
      expect(match.endContainer).toBe(nodes[index]);
      expect(match.endOffset).toBe(3);
    });
  });

  test('async rendering clears old highlights before replacing the DOM and preserves the match index', async () => {
    const { document, window, main, highlights, query, count, matches, current, flushHighlights } =
      nativeFind('<p>old old</p>');
    query('old');
    main._mmdFind.next();
    window.dispatchEvent(new window.Event('scroll'));
    const pending = main.render('old\n\nold\n\nold\n\n```mermaid\ngraph TD; A-->B\n```', 'md');
    expect(highlights.size).toBe(0);
    window.dispatchEvent(new window.Event('resize'));
    flushHighlights();
    expect(highlights.size).toBe(0);
    main._mmdFind.next();
    document
      .querySelector('script[src="mermaid.min.js"]')!
      .dispatchEvent(new window.Event('error'));
    await pending;
    expect(count()).toBe('2/3');
    expectSameRange(current(), matches()[1]);
    expect(document.querySelectorAll('mark')).toHaveLength(0);
  });

  test('CSV paints visible rows while counts, navigation, printing, and font changes retain every match', async () => {
    const { document, window, main, wrap, query, matches, count, flushHighlights } = nativeFind(
      // 間引きは件数が閾値（2,000 件）を超えたときだけ働く。
      '<table>' + '<tr><td>hit</td><td>hit</td></tr>'.repeat(1500) + '</table>',
    );
    const NativeStaticRange = window.StaticRange;
    const allocations = jest
      .spyOn(window, 'StaticRange')
      .mockImplementation((init) => new NativeStaticRange(init));
    const viewport = document.querySelector<HTMLElement>('.viewer')!;
    viewport.getBoundingClientRect = () => new window.DOMRect(0, 0, 800, 100);
    let scroll = 0;
    let rowHeight = 20;
    let measurements = 0;
    const rows = Array.from(wrap.querySelectorAll('tr'));
    rows.forEach((row, index) => {
      row.getBoundingClientRect = () => {
        measurements++;
        return new window.DOMRect(0, index * rowHeight - scroll, 1000, rowHeight);
      };
    });
    query('hit');
    expect(count()).toBe('1/3000');
    expect(matches()).toHaveLength(22);
    expect(allocations).toHaveBeenCalledTimes(23);
    expect(measurements).toBeLessThan(100);
    main._mmdFind.prev();
    expect(count()).toBe('3000/3000');
    scroll = 10000;
    viewport.dispatchEvent(new window.Event('scroll'));
    flushHighlights();
    expect(matches()).toHaveLength(34);
    expect(matches()[0]!.startContainer.parentElement!.closest('tr')).toBe(rows[494]);
    window.dispatchEvent(new window.Event('beforeprint'));
    expect(matches()).toHaveLength(3000);
    window.dispatchEvent(new window.Event('afterprint'));
    expect(matches()).toHaveLength(34);
    rowHeight = 40;
    document.documentElement.style.setProperty('--mmd-code-font-size', '24px');
    await Promise.resolve();
    flushHighlights();
    expect(matches()[0]!.startContainer.parentElement!.closest('tr')).toBe(rows[247]);
    main._mmdCloseFind();
    viewport.dispatchEvent(new window.Event('scroll'));
    flushHighlights();
    expect(matches()).toHaveLength(0);
    allocations.mockRestore();
  });

  test('unnumbered source culls using exact multiline match bounds without dropping results', () => {
    const { document, window, wrap, query, matches, count, flushHighlights } = nativeFind(
      '<pre><code class="csv-source">' + 'hit\n'.repeat(5000) + '</code></pre>',
    );
    // ソース表示ではコードの要素がスクロール対象になる（_mmdScrollTarget）。
    wrap.classList.add('code-body');
    const code = wrap.querySelector('code')!;
    code.getBoundingClientRect = () => new window.DOMRect(0, 0, 800, 100);
    let scroll = 0;
    window.Range.prototype.getBoundingClientRect = function () {
      const first = Math.floor(this.startOffset / 4);
      const last = Math.floor((this.endOffset - 1) / 4);
      return new window.DOMRect(0, first * 20 - scroll, 100, (last - first + 1) * 20);
    };
    document.getElementById('mmd-find-regex')!.click();
    query('hit\\nhit');
    expect(count()).toBe('1/2500');
    expect(matches().length).toBeLessThan(10);
    scroll = 10000;
    code.dispatchEvent(new window.Event('scroll'));
    flushHighlights();
    expect(count()).toBe('1/2500');
    expect(matches().length).toBeLessThan(10);
    expect(matches()[0]!.startOffset).toBe(1976);
  });

  test.each(['rendered', 'source'] as const)(
    'CSV %s cache follows append, refresh, rerender, and reopen',
    async (mode) => {
      const { main, query, matches, current, count } = nativeFind('');
      main.setViewMode(mode);
      await main.render('name\nold\nold\n', 'csv', ',');
      query('old');
      main._mmdFind.next();
      const old = current()!;
      main.appendChunk('old\n', 'csv', ',');
      expect(count()).toBe('2/3');
      (matches().at(-1)!.startContainer as Text).data = 'new';
      main._mmdFindRefresh();
      expect(count()).toBe('2/2');
      await main.render('name\nold\nnew\n', 'csv', ',');
      expect(count()).toBe('1/1');
      expect(old.startContainer.isConnected).toBe(false);
      main._mmdCloseFind();
      await main.render('name\nnew\nold\nold\n', 'csv', ',');
      main._mmdOpenFind();
      expect(count()).toBe('1/2');
    },
  );

  test.each(['markdown-body', 'code-body'])(
    '%s also highlights natively without touching the DOM',
    (className) => {
      const { window, main, wrap, highlights, query, count, matches, current } = nativeFind(
        '<p>' + 'word '.repeat(1000) + '</p>',
      );
      wrap.className = className;
      const original = wrap.innerHTML;
      const mutations = new window.MutationObserver(() => {});
      mutations.observe(wrap, { childList: true, subtree: true, characterData: true });
      query('word');
      expect(count()).toBe('1/1000');
      expect(matches()).toHaveLength(1000);
      expectSameRange(current(), matches()[0]);
      main._mmdFind.prev();
      expectSameRange(current(), matches()[999]);
      query('words');
      expect(matches()).toHaveLength(0);
      query('word');
      main._mmdCloseFind();
      expect(highlights.size).toBe(0);
      expect(mutations.takeRecords()).toEqual([]);
      mutations.disconnect();
      expect(wrap.innerHTML).toBe(original);
    },
  );

  // 間引きの二分探索は「文書順の一致は画面上でも上から下へ並ぶ」前提に立つ。float や
  // position で文書順より上に描かれる内容があるとこれが崩れ、見えている一致を飛ばす
  // ことがある（閉じた <details> の矩形 0 は登録範囲を広げる側で、害はない）。
  // 件数が閾値以下なら間引かず全件を登録して前提を持ち込まない。
  test('document order that disagrees with vertical order still paints every visible match', () => {
    const { window, wrap, query, matches, count } = nativeFind(
      '<p>hit one</p><details><summary>more</summary><p>hit hidden</p></details>' +
        '<p>hit moved</p><p>hit two</p>',
    );
    const top: Record<string, number> = {
      'hit one': 100,
      'hit hidden': 0,
      // 文書順では 3 番目だが、CSS の並べ替えで画面のはるか上に出ている。
      'hit moved': -5000,
      'hit two': 200,
    };
    window.Range.prototype.getBoundingClientRect = function () {
      const y = top[this.startContainer.textContent ?? ''] ?? 0;
      return y === 0 ? new window.DOMRect(0, 0, 0, 0) : new window.DOMRect(0, y, 20, 16);
    };
    query('hit');
    expect(count()).toBe('1/4');
    const painted = matches().map((match) => match.startContainer.textContent);
    expect(painted).toEqual(expect.arrayContaining(['hit one', 'hit two']));
    expect(wrap.querySelectorAll('mark')).toHaveLength(0);
  });

  // 閾値を超えた Markdown（<tr> が無く Range の矩形で測る経路）でも間引きが働き、
  // スクロールで登録範囲が追従する。
  test('markdown above the threshold culls by range bounds and follows scrolling', () => {
    const { window, document, query, matches, count, flushHighlights } = nativeFind(
      '<p>hit</p>'.repeat(2500),
    );
    const viewer = document.querySelector<HTMLElement>('.viewer')!;
    viewer.getBoundingClientRect = () => new window.DOMRect(0, 0, 800, 100);
    let scroll = 0;
    const paragraphs = Array.from(document.querySelectorAll('#diagram-wrap p'));
    window.Range.prototype.getBoundingClientRect = function () {
      const index = paragraphs.indexOf(this.startContainer.parentElement!);
      return new window.DOMRect(0, index * 20 - scroll, 20, 16);
    };
    query('hit');
    expect(count()).toBe('1/2500');
    expect(matches().length).toBeLessThan(20);
    expect(matches()[0]!.startContainer.parentElement).toBe(paragraphs[0]);
    scroll = 10000;
    viewer.dispatchEvent(new window.Event('scroll'));
    flushHighlights();
    expect(matches().length).toBeLessThan(20);
    expect(matches()[0]!.startContainer.parentElement).toBe(paragraphs[495]);
  });

  // 図のズーム操作（− 100% ＋）は文書の内容ではなく、倍率を変えると label のテキスト
  // ノードが差し替わる。索引に入れると件数に混ざり、切り離されたノードを指す一致が残る。
  test('diagram zoom controls are neither counted nor indexed', () => {
    const { document, query, count, matches } = nativeFind(
      '<div class="diagram-zoom-wrap"><div class="diagram-zoom-controls">' +
        '<button>−</button><span class="diagram-zoom-label">100%</span><button>+</button>' +
        '</div></div><p>100% done</p>',
    );
    query('100%');
    expect(count()).toBe('1/1');
    document.querySelector('.diagram-zoom-label')!.textContent = '150%';
    query('100%');
    expect(matches()[0]!.startContainer.isConnected).toBe(true);
    expect(count()).toBe('1/1');
  });

  test('navigation reveals an exact match through horizontal and vertical containers at 200% zoom', () => {
    const { window, document, wrap, query } = nativeFind(
      '<div class="csv-scroll"><table><tr><td>match</td></tr></table></div>',
    );
    const horizontal = wrap.querySelector<HTMLElement>('.csv-scroll')!;
    const viewer = document.querySelector<HTMLElement>('.viewer')!;
    horizontal.style.overflowX = 'auto';
    viewer.style.overflowY = 'auto';
    for (const [element, values] of [
      [
        horizontal,
        {
          offsetWidth: 400,
          clientWidth: 400,
          scrollWidth: 1200,
          clientHeight: 1000,
          scrollHeight: 1000,
        },
      ],
      [
        viewer,
        {
          offsetWidth: 800,
          clientWidth: 800,
          scrollWidth: 800,
          clientHeight: 400,
          scrollHeight: 4000,
        },
      ],
    ] as const) {
      Object.entries(values).forEach(([key, value]) => {
        Object.defineProperty(element, key, { value });
      });
    }
    horizontal.getBoundingClientRect = () => new window.DOMRect(0, 0, 800, 2000);
    viewer.getBoundingClientRect = () => new window.DOMRect(0, 0, 800, 400);
    window.Range.prototype.getBoundingClientRect = () => new window.DOMRect(1400, 1200, 100, 20);
    const scrollHorizontal = jest.fn<(options?: ScrollToOptions | number, y?: number) => void>();
    const scrollViewer = jest.fn<(options?: ScrollToOptions | number, y?: number) => void>();
    horizontal.scrollTo = scrollHorizontal;
    viewer.scrollTo = scrollViewer;
    query('match');
    expect(scrollHorizontal).toHaveBeenCalledWith({ left: 350, top: 0, behavior: 'smooth' });
    expect(scrollViewer).toHaveBeenCalledWith({ left: 0, top: 1010, behavior: 'smooth' });
  });
});
