// XSL スタイルシートを伴う XML の XSLT 変換表示（TASK-596）。
//
// 変換そのものは WebKit 同梱の XSLTProcessor が行う。jsdom には XSLTProcessor が
// 無いため、ここではスタブを置いて「呼び出しの形」と「失敗時にソース表示へ落ちること」を
// 固定する。実 WKWebView 上で XSLTProcessor が動くことはタスクの Notes に実測がある。

const { JSDOM } = require('jsdom');

const { _renderXslt } = require('../../../viewer-src/main.js');

const dom = new JSDOM('<div id="diagram-wrap"></div>');

/**
 * 変換結果として fragment を返すスタブ。
 * onImport を渡すと importStylesheet の時点でそれを呼ぶ（例外経路の再現に使う）。
 */
function installXSLTProcessor(makeFragment, onImport) {
  global.XSLTProcessor = class {
    importStylesheet() {
      if (onImport) {
        onImport();
      }
    }
    transformToFragment() {
      return makeFragment(dom.window.document);
    }
  };
}

let diagramWrap;

beforeEach(() => {
  global.document = dom.window.document;
  global.DOMParser = dom.window.DOMParser;
  diagramWrap = dom.window.document.getElementById('diagram-wrap');
  diagramWrap.className = '';
  diagramWrap.innerHTML = '';
});

afterEach(() => {
  delete global.XSLTProcessor;
});

const payload = (xml, xsl) => JSON.stringify({ xml, xsl });
const VALID_XSL =
  '<?xml version="1.0"?><xsl:stylesheet version="1.0" ' +
  'xmlns:xsl="http://www.w3.org/1999/XSL/Transform"><xsl:template match="/"/></xsl:stylesheet>';

describe('_renderXslt', () => {
  test('変換結果を xslt-body として差し込む', () => {
    installXSLTProcessor((d) => {
      const fragment = d.createDocumentFragment();
      const div = d.createElement('div');
      div.textContent = 'こんにちは';
      fragment.append(div);
      return fragment;
    });

    const result = _renderXslt(diagramWrap, payload('<doc/>', VALID_XSL));

    expect(result).toEqual({ shape: 'xslt', error: null });
    expect(diagramWrap.classList.contains('xslt-body')).toBe(true);
    expect(diagramWrap.innerHTML).toBe('<div>こんにちは</div>');
  });

  // AC#4: 出力は markdown と同じサニタイズ経路（DOMPurify）を通してから差し込む。
  test('変換結果に含まれるスクリプトはサニタイズで落ちる', () => {
    installXSLTProcessor((d) => {
      const fragment = d.createDocumentFragment();
      const div = d.createElement('div');
      div.innerHTML = '<p>本文</p><script>alert(1)</script>';
      fragment.append(div);
      return fragment;
    });

    _renderXslt(diagramWrap, payload('<doc/>', VALID_XSL));

    expect(diagramWrap.innerHTML).toContain('<p>本文</p>');
    expect(diagramWrap.innerHTML).not.toContain('<script>');
  });

  // AC#6: 不正な入力でも投げず、理由を返して原文のソース表示へ落ちる。
  test('xml が不正なら理由を返し、原文をソース表示へ落とす', () => {
    installXSLTProcessor(() => null);

    const result = _renderXslt(diagramWrap, payload('<doc><unclosed>', VALID_XSL));

    expect(result.shape).toBe('code');
    expect(result.error).toBeTruthy();
    expect(diagramWrap.classList.contains('xslt-body')).toBe(false);
    expect(diagramWrap.textContent).toContain('unclosed');
  });

  test('xsl が不正なら理由を返し、原文をソース表示へ落とす', () => {
    installXSLTProcessor(() => null);

    const result = _renderXslt(diagramWrap, payload('<doc>本文</doc>', '<xsl:stylesheet'));

    expect(result.shape).toBe('code');
    expect(result.error).toBeTruthy();
    expect(diagramWrap.textContent).toContain('本文');
  });

  test('変換が何も返さなければ理由を返し、原文をソース表示へ落とす', () => {
    installXSLTProcessor(() => null);

    const result = _renderXslt(diagramWrap, payload('<doc>本文</doc>', VALID_XSL));

    expect(result.shape).toBe('code');
    expect(result.error).toBe('XSLT transform produced no output');
    expect(diagramWrap.textContent).toContain('本文');
  });

  test('importStylesheet が投げても伝播させずソース表示へ落とす', () => {
    installXSLTProcessor(
      () => null,
      () => {
        throw new Error('boom');
      },
    );

    const result = _renderXslt(diagramWrap, payload('<doc>本文</doc>', VALID_XSL));

    expect(result.shape).toBe('code');
    expect(result.error).toContain('boom');
  });

  test('content が JSON でなければ、その内容をそのままソース表示へ出す', () => {
    installXSLTProcessor(() => null);

    const result = _renderXslt(diagramWrap, 'not json');

    expect(result.shape).toBe('code');
    expect(result.error).toBeTruthy();
    expect(diagramWrap.textContent).toContain('not json');
  });
});
