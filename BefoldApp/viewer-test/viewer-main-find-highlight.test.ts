import { describe, expect, jest, test } from '@jest/globals';

import { loadViewerMain } from './support/viewerMainHarness.js';

function nativeFind(html: string) {
  const loaded = loadViewerMain();
  const { window, document, main } = loaded;
  const highlights = new Map<string, Set<StaticRange>>();
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

  Object.defineProperty(window, 'CSS', { value: { highlights }, configurable: true });
  window.Highlight = class extends Set<AbstractRange> {
    priority = 0;
    type: HighlightType = 'highlight';
    constructor(...ranges: AbstractRange[]) {
      super(ranges);
    }
  };
  window.Range.prototype.getBoundingClientRect = () => new window.DOMRect(0, 0, 20, 16);
  const wrap = document.getElementById('diagram-wrap')!;
  wrap.innerHTML = html;
  wrap.classList.add(wrap.querySelector('code.csv-source') ? 'code-body' : 'csv-body');
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

  test('async rendering clears old highlights before replacing the DOM and preserves the match index', async () => {
    const { document, window, main, highlights, query, count, flushHighlights } =
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
    expect(document.querySelector('.mmd-find-match-current')).toBe(
      document.querySelectorAll('mark.mmd-find-match')[1],
    );
    expect(highlights.size).toBe(0);
  });

  test('CSV paints visible rows while counts, navigation, printing, and font changes retain every match', async () => {
    const { document, window, main, wrap, query, matches, count, flushHighlights } = nativeFind(
      '<table>' + '<tr><td>hit</td><td>hit</td></tr>'.repeat(1000) + '</table>',
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
    expect(count()).toBe('1/2000');
    expect(matches()).toHaveLength(22);
    expect(allocations).toHaveBeenCalledTimes(23);
    expect(measurements).toBeLessThan(100);
    main._mmdFind.prev();
    expect(count()).toBe('2000/2000');
    scroll = 10000;
    viewport.dispatchEvent(new window.Event('scroll'));
    flushHighlights();
    expect(matches()).toHaveLength(34);
    expect(matches()[0]!.startContainer.parentElement!.closest('tr')).toBe(rows[494]);
    window.dispatchEvent(new window.Event('beforeprint'));
    expect(matches()).toHaveLength(2000);
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
      '<pre><code class="csv-source">' + 'hit\n'.repeat(1000) + '</code></pre>',
    );
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
    expect(count()).toBe('1/500');
    expect(matches().length).toBeLessThan(10);
    scroll = 10000;
    code.dispatchEvent(new window.Event('scroll'));
    flushHighlights();
    expect(count()).toBe('1/500');
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
    '%s retains marks even when native APIs exist',
    (className) => {
      const { main, wrap, highlights, query, count } = nativeFind(
        '<p>' + 'word '.repeat(1000) + '</p>',
      );
      wrap.className = className;
      query('word');
      expect(count()).toBe('1/1000');
      expect(wrap.querySelectorAll('mark')).toHaveLength(1000);
      expect(wrap.querySelector('.mmd-find-match-current')).toBe(wrap.querySelector('mark'));
      main._mmdFind.prev();
      expect(wrap.querySelector('.mmd-find-match-current')).toBe(
        wrap.querySelectorAll('mark')[999],
      );
      expect(highlights.size).toBe(0);
      query('words');
      expect(wrap.querySelectorAll('mark')).toHaveLength(0);
      query('word');
      main._mmdCloseFind();
      expect(wrap.querySelectorAll('mark')).toHaveLength(0);
      expect(highlights.size).toBe(0);
    },
  );

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
