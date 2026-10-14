// CLI の `--line` が使う _mmdRevealLine の振る舞い(TASK-701)。
//
// 要求は描画より先に届くことがあり、行は段階読み込みでまだ DOM に無いことがある。
// そのため「保留して、描画・追記・読み込み状態の変化のたびに試す」ことを固定する。
import { describe, expect, test } from '@jest/globals';

import {
  captureBridgeMessages,
  loadViewerMain,
  type LoadedViewer,
} from './support/viewerMainHarness.js';

const PATH = '/repo/a.swift';

function lines(count: number, from = 1): string {
  return Array.from({ length: count }, (_, i) => `line ${from + i}`).join('\n') + '\n';
}

// jsdom の scrollIntoView はレイアウトを持たないスタブ。どの行が先頭へ出されたかを記録する。
function trackScrolledRows(loaded: LoadedViewer): string[] {
  const scrolled: string[] = [];
  loaded.window.Element.prototype.scrollIntoView = function (this: Element) {
    scrolled.push(this.textContent ?? '');
  };
  return scrolled;
}

async function renderSource(loaded: LoadedViewer, content: string, path = PATH) {
  loaded.main._mmdSetRenderDocPath(path);
  loaded.main.setViewMode('source');
  await loaded.main.render(content, 'code', 'swift');
}

describe('_mmdRevealLine', () => {
  test('描画済みのソース表示なら即座にその行を先頭へ出す', async () => {
    const loaded = loadViewerMain({});
    await renderSource(loaded, lines(50));
    const scrolled = trackScrolledRows(loaded);

    loaded.main._mmdRevealLine(PATH, 42);

    expect(scrolled).toHaveLength(1);
    expect(scrolled[0]).toContain('line 42');
  });

  test('描画より先に届いた要求は保留され、描画の直後に満たされる', async () => {
    const loaded = loadViewerMain({});
    const scrolled = trackScrolledRows(loaded);

    loaded.main._mmdRevealLine(PATH, 7);
    expect(scrolled).toEqual([]);
    await renderSource(loaded, lines(50));

    expect(scrolled).toHaveLength(1);
    expect(scrolled[0]).toContain('line 7');
  });

  test('一度満たした要求は、再描画では繰り返されない', async () => {
    const loaded = loadViewerMain({});
    const scrolled = trackScrolledRows(loaded);
    loaded.main._mmdRevealLine(PATH, 3);
    await renderSource(loaded, lines(10));

    await loaded.main.render(lines(10), 'code', 'swift');

    expect(scrolled).toHaveLength(1);
  });

  test('別の文書が描画されたら要求は捨てられる', async () => {
    const loaded = loadViewerMain({});
    const scrolled = trackScrolledRows(loaded);
    loaded.main._mmdRevealLine(PATH, 3);

    await renderSource(loaded, lines(10), '/repo/other.swift');
    await renderSource(loaded, lines(10), PATH);

    expect(scrolled).toEqual([]);
  });

  test('この文書では行を出せない形(レンダリング表示)で描画されたら捨てられる', async () => {
    const loaded = loadViewerMain({});
    const scrolled = trackScrolledRows(loaded);
    loaded.main._mmdRevealLine(PATH, 3);
    loaded.main._mmdSetRenderDocPath(PATH);
    loaded.main.setViewMode('rendered');
    await loaded.main.render('# title\n', 'md');

    loaded.main.setViewMode('source');
    await loaded.main.render(lines(10), 'code', 'swift');

    expect(scrolled).toEqual([]);
  });

  describe('段階読み込み', () => {
    async function openTruncated(loaded: LoadedViewer, requested: number) {
      const messages = captureBridgeMessages(loaded.window, ['loadMoreLines']);
      loaded.main._mmdSetTruncated(true, 10, false);
      loaded.main._mmdRevealLine(PATH, requested);
      await renderSource(loaded, lines(10));
      return messages;
    }

    test('行が未読み込みなら続きを依頼し、届いた時点で満たす', async () => {
      const loaded = loadViewerMain({});
      const scrolled = trackScrolledRows(loaded);

      const messages = await openTruncated(loaded, 25);
      expect(messages.map((m) => m.name)).toEqual(['loadMoreLines']);
      expect(scrolled).toEqual([]);

      loaded.main.appendChunk(lines(10, 11), 'code', 'swift');
      // まだ足りない: 続きを重ねて依頼するが、スクロールはしない。
      expect(messages).toHaveLength(2);
      expect(scrolled).toEqual([]);

      loaded.main.appendChunk(lines(10, 21), 'code', 'swift');
      expect(messages).toHaveLength(2);
      expect(scrolled).toHaveLength(1);
      expect(scrolled[0]).toContain('line 25');
    });

    test('依頼の応答を待つ間は重ねて依頼しない', async () => {
      const loaded = loadViewerMain({});
      const messages = await openTruncated(loaded, 25);

      loaded.main._mmdSetTruncated(true, 10, false);

      // 読み込み状態の通知だけでは依頼し直さない(チャンクごとの依頼が 2 回に膨らむ)。
      expect(messages).toHaveLength(1);
    });

    test('末尾まで読んでも行が無ければ末尾の行へ寄せる', async () => {
      const loaded = loadViewerMain({});
      const scrolled = trackScrolledRows(loaded);
      await openTruncated(loaded, 99);

      // 実際の順序: 読み込み状態(末尾に達した)が先、最後のチャンクの追記が後。
      // 非切り詰め時の行数は Swift が 0 に正規化する(TruncationState)。
      loaded.main._mmdSetTruncated(false, 0, false);
      expect(scrolled).toEqual([]);
      loaded.main.appendChunk(lines(5, 11), 'code', 'swift');

      expect(scrolled).toHaveLength(1);
      expect(scrolled[0]).toContain('line 15');
    });

    // Swift は読み込み状態(末尾に達した)を送ってから、最後のチャンクを追記する。
    // 実機で、依頼中にこの通知を「もう無い」と解釈して 2000 行目へ寄せてしまった。
    test('末尾に達した通知が最後のチャンクの追記より先に届いても、追記後にその行へ出す', async () => {
      const loaded = loadViewerMain({});
      const scrolled = trackScrolledRows(loaded);
      await openTruncated(loaded, 25);

      loaded.main._mmdSetTruncated(false, 0, false);
      expect(scrolled).toEqual([]);
      loaded.main.appendChunk(lines(20, 11), 'code', 'swift');

      expect(scrolled).toHaveLength(1);
      expect(scrolled[0]).toContain('line 25');
    });

    test('続きを待っている間に再描画されたら要求は捨てられ、後の再描画で飛ばない', async () => {
      const loaded = loadViewerMain({});
      const scrolled = trackScrolledRows(loaded);
      await openTruncated(loaded, 99);

      await loaded.main.render(lines(10), 'code', 'swift');
      loaded.main._mmdSetTruncated(false, 10, false);
      await loaded.main.render(lines(10), 'code', 'swift');

      expect(scrolled).toEqual([]);
    });

    test('続きの読み込みに失敗したら、読めた範囲の末尾へ寄せる', async () => {
      const loaded = loadViewerMain({});
      const scrolled = trackScrolledRows(loaded);
      await openTruncated(loaded, 99);

      loaded.main._mmdSetTruncated(true, 10, true);

      expect(scrolled).toHaveLength(1);
      expect(scrolled[0]).toContain('line 10');
    });

    test('続きを依頼できないホストでは待たずに末尾へ寄せる', async () => {
      const loaded = loadViewerMain({ hostFeatures: { loadMore: false } });
      const scrolled = trackScrolledRows(loaded);
      loaded.main._mmdSetTruncated(true, 10, false);
      loaded.main._mmdRevealLine(PATH, 99);

      await renderSource(loaded, lines(10));

      expect(scrolled).toHaveLength(1);
      expect(scrolled[0]).toContain('line 10');
    });
  });
});
