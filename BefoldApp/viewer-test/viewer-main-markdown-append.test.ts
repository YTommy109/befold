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
