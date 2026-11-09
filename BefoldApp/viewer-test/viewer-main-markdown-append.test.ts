import { describe, expect, test } from '@jest/globals';

import { captureBridgeMessages, loadViewerMain } from './support/viewerMainHarness.js';

describe('Markdown 追記のパス注釈', () => {
  test('既存本文を走査し直さず、追記した参照だけを解決する', async () => {
    const { document, window, main } = loadViewerMain();
    const received = captureBridgeMessages(window, ['resolveReferences']);
    await main.render('<p id="old"><strong>既存</strong> src/old.md</p>\n\n', 'md');
    main._mmdApplyResolvedReferences({ 'src/old.md': '/repo/src/old.md' });
    received.length = 0;
    const old = document.getElementById('old')!;
    const originalHtml = old.innerHTML;
    const originalChildren = old.childNodes;
    let reads = 0;
    // 時間の閾値ではなく、読み込み済み本文への再走査を検出する。
    Object.defineProperty(old, 'childNodes', {
      get: () => {
        reads++;
        return originalChildren;
      },
    });

    main.appendChunk('src/new.md\n\n', 'md');
    main.appendChunk('`src/next.ts`\n\n', 'md');

    expect(reads).toBe(0);
    expect(document.getElementById('old')).toBe(old);
    expect(old.innerHTML).toBe(originalHtml);
    expect(received.map((message) => message.payload)).toEqual([
      { paths: ['src/new.md'] },
      { paths: ['src/next.ts'] },
    ]);
    main._mmdApplyResolvedReferences({ 'src/new.md': '/repo/src/new.md' });
    main._mmdApplyResolvedReferences({ 'src/next.ts': '/repo/src/next.ts' });
    expect(
      Array.from(
        document.querySelectorAll<HTMLElement>('#diagram-wrap .befold-link'),
        (el) => el.dataset.resolved,
      ),
    ).toEqual(['/repo/src/old.md', '/repo/src/new.md', '/repo/src/next.ts']);
  });

  test.each(['', '<div>既存</div>', '<div>既存</div>末尾の裸テキスト'])(
    '初期本文 %j への追記でも注釈対象と除外範囲を保つ',
    async (initial) => {
      const { document, main } = loadViewerMain();
      await main.render(initial, 'md');
      const wrap = document.getElementById('diagram-wrap')!;
      const originalNodes = Array.from(wrap.childNodes);
      const originalText = wrap.textContent;
      const chunk = [
        '<div>src/bare.md <span>src/span.md</span> <code>src/inline.ts</code></div>',
        '<p>src/<em>split.py</em></p>',
        '<pre>src/excluded.md <code>src/code.rs</code></pre>',
        '<p><a href="https://example.invalid">src/link.md</a></p>',
        '<svg><text>src/diagram.md</text></svg>',
        '<div class="mermaid" data-processed="true">src/mermaid.md</div>',
        '',
      ].join('\n');

      main.appendChunk(chunk, 'md');

      originalNodes.forEach((node, index) => expect(wrap.childNodes[index]).toBe(node));
      expect(wrap.textContent!.startsWith(originalText!)).toBe(true);
      expect(
        Array.from(wrap.querySelectorAll<HTMLElement>('.befold-path-ref'), (el) => el.dataset.path),
      ).toEqual(['src/inline.ts', 'src/split.py', 'src/split.py', 'src/code.rs']);
      expect(wrap.querySelector('pre')!.textContent).toBe('src/excluded.md src/code.rs');
      expect(wrap.querySelector('svg')!.textContent).toBe('src/diagram.md');
      expect(wrap.querySelector('a')!.textContent).toBe('src/link.md');
    },
  );
});

const fence = (name: string) => `\`\`\`mermaid\ngraph TD; ${name}-->${name}2;\n\`\`\`\n\n`;

describe('Mermaid の実行が重なったときの図の枠', () => {
  const RENDERED_HEIGHT = 600;
  const SOURCE_HEIGHT = 20;

  // 本物の mermaid.run と同じ形の偽物: 図を 1 個ずつ処理し、data-processed は描画の
  // await より前に付く。実行どうしは直列化しない。描画は release で 1 件ずつ終える。
  function setUp() {
    const loaded = loadViewerMain();
    const { window, document } = loaded;
    const pending: Array<() => void> = [];
    const runNodes: HTMLElement[][] = [];
    Object.assign(window, {
      mermaid: {
        initialize: () => {},
        run: async ({ nodes }: { nodes: HTMLElement[] }) => {
          runNodes.push(nodes);
          for (const node of nodes) {
            if (node.dataset.processed) continue;
            node.dataset.processed = 'true';
            // 本物と同じく図を 1 個ずつ順に描画する。
            // oxlint-disable-next-line no-await-in-loop
            await new Promise<void>((resolve) => {
              pending.push(resolve);
            });
            node.innerHTML = '<svg></svg>';
          }
        },
      },
    });
    Object.defineProperty(window.HTMLElement.prototype, 'offsetHeight', {
      configurable: true,
      get(this: HTMLElement) {
        return this.querySelector('svg') ? RENDERED_HEIGHT : SOURCE_HEIGHT;
      },
    });
    const flush = () =>
      new Promise((resolve) => {
        window.setTimeout(resolve, 0);
      });
    const finishMermaidLoad = async () => {
      await flush();
      document
        .querySelector('script[src="mermaid.min.js"]')!
        .dispatchEvent(new window.Event('load'));
      await flush();
    };
    const releaseAll = async () => {
      while (pending.length > 0) {
        pending.shift()!();
        // 描画を 1 件ずつ終え、そのたびに後続の継続を走らせるため順番に待つ。
        // oxlint-disable-next-line no-await-in-loop
        await flush();
      }
    };
    const naturalHeights = () =>
      Array.from(
        document.querySelectorAll<HTMLElement>('#diagram-wrap .diagram-zoom-wrap'),
        (wrap) => Number(wrap.dataset.naturalHeight),
      );
    return { ...loaded, pending, runNodes, finishMermaidLoad, releaseAll, naturalHeights, flush };
  }

  test('先の実行の完了時に、後から追記した描画前の図を包まない', async () => {
    const { main, pending, finishMermaidLoad, releaseAll, naturalHeights, flush } = setUp();
    await main.render('# t\n', 'md');
    main.appendChunk(fence('A'), 'md');
    await finishMermaidLoad();
    main.appendChunk(fence('B'), 'md');
    await flush();

    pending.shift()!();
    await flush();
    expect(naturalHeights()).toEqual([RENDERED_HEIGHT]);

    await releaseAll();
    expect(naturalHeights()).toEqual([RENDERED_HEIGHT, RENDERED_HEIGHT]);
  });

  test('図 2 個の実行の途中で追記しても、残りの図を奪って描画前に包まない', async () => {
    const { main, finishMermaidLoad, releaseAll, naturalHeights, flush } = setUp();
    await main.render('# t\n', 'md');
    main.appendChunk(fence('A') + fence('B'), 'md');
    await finishMermaidLoad();
    main.appendChunk(fence('C'), 'md');
    await flush();

    await releaseAll();

    expect(naturalHeights()).toEqual([RENDERED_HEIGHT, RENDERED_HEIGHT, RENDERED_HEIGHT]);
  });

  test('render が重なっても、最新の DOM の図を 1 度しか描画しない', async () => {
    const { main, document, runNodes, finishMermaidLoad, releaseAll, naturalHeights } = setUp();
    void main.render(fence('A'), 'md');
    void main.render(fence('B'), 'md');
    const last = main.render(fence('C'), 'md');
    const latest = document.querySelector<HTMLElement>('#diagram-wrap .mermaid')!;
    await finishMermaidLoad();

    await releaseAll();
    await last;

    expect(runNodes.filter((nodes) => nodes.includes(latest))).toHaveLength(1);
    expect(latest.querySelector('svg')).not.toBeNull();
    expect(naturalHeights()).toEqual([RENDERED_HEIGHT]);
  });
});
