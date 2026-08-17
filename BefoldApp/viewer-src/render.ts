// 描画の入口(render)とチャンク追記(appendChunk)のディスパッチ。
// 「いま何の形を描いたか」の記録もここが持ち、書き手をこの 1 モジュールに閉じる。

import { buildLineNumberRows, codeChunkInnerHtml, lastLines } from './code-html.js';
import { csvRowsHtml, csvSourceInnerHtml, parseCsv } from './csv-html.js';
import { _mmdChunkTail, _mmdDocument } from './document-state.js';
import { _mmdFind } from './find.js';
import { _mmdJump } from './jump.js';
import { markdownRenderer } from './markdown.js';
import { _mmdRunMermaid } from './mermaid.js';
import {
  _annotatePathRefs,
  _mmdInvalidatePendingRefs,
  _mmdResolveReferences,
  _walkTextNodes,
} from './path-refs.js';
import {
  _mmdPdfBlob,
  _mmdSetBodyClasses,
  _renderCsv,
  _renderHtml,
  _renderImage,
  _renderMarkdown,
  _renderMmd,
  _renderPdf,
  _renderSource,
  _renderSvg,
} from './renderers.js';
import { _mmdRestoreScrollPosition, _mmdScroll, _mmdScrollTarget } from './scroll.js';
import { hljs } from './vendor.js';
import { _mmdModeSwitch, _mmdViewOptions } from './view-options.js';
import { _mmdApplyZoom } from './zoom.js';

// 表示モードとファイル種別から「いま #diagram-wrap に描く形」を決める。
//
// この 1 つの値が render() の分岐と appendChunk() の追記戦略の両方の元になる。
// 判定が 2 箇所に分かれていた頃は、ソース表示中の追記が type だけで md と
// 判断され、行番号付きソースの下に描画済み Markdown が挟まった(TASK-414)。
//
// 返す値は追記戦略と 1 対 1 に対応する:
//   'code'       行番号付きコード表(ソース表示のテキスト種別と、常にソースのコード種別)
//   'csv-source' CSV/TSV のソース表示(列ごとのレインボー着色。独自の列構造を持つ)
//   'csv-table'  CSV/TSV のレンダリング表示(HTML テーブル)
//   'markdown'   Markdown のレンダリング表示
//   その他       種別名そのまま(mmd/svg/html/image/pdf。いずれも追記の対象外)
//
// 画像・PDF とコード種別はソース表示を持たないため、モードで形が変わらない。
function renderShape(type: string, mode: 'rendered' | 'source'): string {
  if (mode === 'source' && type !== 'code' && type !== 'image' && type !== 'pdf') {
    return type === 'csv' ? 'csv-source' : 'code';
  }
  if (type === 'code') {
    return 'code';
  }
  if (type === 'csv') {
    return 'csv-table';
  }
  if (type === 'md') {
    return 'markdown';
  }
  return type;
}

// 直前の render() が実際に描いた形(renderShape の戻り値、または差分なら 'diff')。
// 書き手は render() だけで、モジュールの外へは公開しない。
//
// appendChunk はこの値だけを見て追記戦略を決める。表示モードや type から
// 推し直すと、render 側と別々に判定が育って食い違う(TASK-414)。DOM の形
// (table.diff-table や pre code.csv-source)を探す判定も使わない。同じ形は
// markdown-it が html:true で通したユーザーコンテンツにも現れる(TASK-339)。
// 戻り値を RenderShape の union にしないのは、未知の種別名が届いたときに
// そのまま返って render() の else 節(Markdown 描画)へ落ちる経路が実在し、
// union で閉じるとその経路が型の上から消えるため。
var _mmdRenderedAs = '';

// appendChunk でのハイライトに与える前方文脈の行数。ブロックコメントや
// 複数行文字列がチャンク境界をまたいでも hljs が字句状態を再構築できる
// ようにするための固定サイズの先読み(詳細は codeChunkInnerHtml 参照)。
var CODE_CHUNK_CONTEXT_LINES = 200;

// render() / appendChunk() の末尾で、検索と文書内ジャンプの状態を再描画後の
// 内容に合わせて更新する。
// 持ち越しフラグはバーの開閉に関わらずここで必ず消費する(閉じている間に
// 溜めておくと、次にバーを開いたときに無関係な先頭リセットが起きるため)。
// consume() は破壊的読み出しなので、呼ぶのはこの 1 箇所だけにして、
// 得た値を検索とジャンプの両方へ渡す(2 回呼ぶと後の 1 回が必ず false を受け取り、
// 片方だけモード切替を観測しない)。
function _mmdFindRefreshAfterRender(): void {
  var modeJustSwitched = _mmdModeSwitch.consume();
  if (_mmdFind.isOpen()) {
    _mmdFind.refresh(modeJustSwitched);
  }
  if (_mmdJump.isOpen()) {
    _mmdJump.refresh(modeJustSwitched);
  }
}

async function render(content: string, type: string, lang: string | undefined): Promise<void> {
  _mmdScroll.beginRender();
  // 描画の着地まで（mermaid の描画を await する間）DOM は既に差し替わっている。
  // 目印の列は列そのものが状態なので、ここで捨てておかないと前の文書の
  // n/N と現在位置ハイライトがその間ずっと表示され続ける。
  _mmdJump.invalidate();
  // DOM を書き換える前に、内部再描画(カラースキーム変更時など)向けの
  // フォールバック復元位置として現在位置を退避する(_mmdRestoreScrollPosition 参照)。
  var scrollTargetBeforeRender = _mmdScrollTarget();
  var fallbackScrollTop = scrollTargetBeforeRender ? scrollTargetBeforeRender.scrollTop : 0;
  _mmdDocument.record(content, type, lang);
  // 初回チャンクも LineChunkReader の強制分割で改行なしのまま渡ることがあるため、
  // appendChunk と同じ判定式で実際の末尾を見る(true 固定だと最初の強制分割で
  // 継続行の結合判定を誤る)。
  _mmdChunkTail.record(content);
  // いま描く形をここで 1 回だけ決め、appendChunk が読む記録にする。分岐へ入る前に
  // 記録するのは、どの経路を通っても記録が確定するようにするため(後で入れ直す形に
  // すると、途中で返る経路だけ前回の値が残って追記戦略が食い違う)。
  // 差分を組み上げた場合だけ _renderSource が 'diff' を返し、下で上書きする。
  var shape = renderShape(type, _mmdViewOptions.mode());
  _mmdRenderedAs = shape;
  // 以降で #diagram-wrap を作り直すため、旧 DOM を指す未応答の解決バッチを無効化する。
  _mmdInvalidatePendingRefs();
  // #mmd-error と #diagram-wrap は viewer.html に静的に置かれており、
  // バンドルを読む時点で必ず存在する(非 null 表明の理由は truncation.ts と同じ)。
  var errorPanel = document.getElementById('mmd-error')!;
  errorPanel.style.display = 'none';
  errorPanel.textContent = '';
  var diagramWrap = document.getElementById('diagram-wrap')!;
  diagramWrap.style.display = 'block';

  // 分岐前に一括で外し、各分岐は自分のクラスを add するだけにする。
  _mmdSetBodyClasses(diagramWrap);

  // 前回の PDF 表示で生成した blob URL を解放する(PDF 以外への切替も含む)。
  _mmdPdfBlob.release();

  // 描画形ディスパッチ。中身の組み立ては各ビルダーに委ね、ここでは選ぶだけにする。
  if (shape === 'code' || shape === 'csv-source') {
    _mmdRenderedAs = _renderSource(diagramWrap, content, type, lang, shape);
  } else if (shape === 'mmd') {
    _renderMmd(diagramWrap, content);
  } else if (shape === 'svg') {
    _renderSvg(diagramWrap, content);
  } else if (shape === 'html') {
    _renderHtml(diagramWrap, content);
  } else if (shape === 'csv-table') {
    _renderCsv(diagramWrap, content, lang);
  } else if (shape === 'image') {
    _renderImage(diagramWrap, content, lang);
  } else if (shape === 'pdf') {
    _renderPdf(diagramWrap, content);
  } else {
    _renderMarkdown(diagramWrap, content);
  }

  await _mmdRunMermaid(diagramWrap);

  _annotatePathRefs();
  _mmdResolveReferences();
  _mmdFindRefreshAfterRender();
  _mmdApplyZoom();
  _mmdRestoreScrollPosition(fallbackScrollTop);
}

// 直近の内容をそのまま描き直す(カラースキーム変更などの内部再描画)。
// まだ何も描いていなければ何もしない(content() が null かどうかで判定する。
// hasContent() 経由だと、同じ判定でも型の上では content が null のまま残る)。
function _mmdRerenderCurrent(): void {
  var content = _mmdDocument.content();
  if (content === null) {
    return;
  }
  // 完了を待つ呼び出し元が居ない内部再描画。握り潰しではなく「待たない」ことを void で明示する。
  void render(content, _mmdDocument.type(), _mmdDocument.lang());
}

// 追加読み込みされたチャンクを既存 DOM に追記する(Swift の ViewerBridge から呼ばれる)。
// HTML 組み立ては純粋関数(csvRowsHtml / buildLineNumberRows / codeChunkInnerHtml)に
// 委ね、ここでは DOM 挿入のみ行う。パス注釈は追記した行だけを _walkTextNodes で
// 処理し、追記コストを O(チャンク) に抑える。
//
// `type` は render() と同じ呼び出し形(ViewerBridge.contentCallScript)で届くだけで、
// **追記先の分岐には使わない**。同じ type でも表示モードや差分の有無で DOM の形は
// 変わるため、type から推し直すと render 側の判定と食い違う(TASK-414)。
// 分岐は _mmdRenderedAs(render が実際に描いた形)だけを見ること。
function appendChunk(text: string, type: string, lang: string | undefined): void {
  // 空チャンク(チャンク読込エラー時のセンチネル)は追記する内容がない。
  // buildLineNumberRows('') は初回描画(空ファイル1行目)用に空行1つを返す契約のため、
  // ここで弾かないと既存テーブルの末尾に幻の空行が増えてしまう。
  if (!text) {
    return;
  }
  var diagramWrap = document.getElementById('diagram-wrap');
  if (!diagramWrap) {
    return;
  }
  // 直前チャンクが改行で終わっている(=行境界で分割された)場合のみ、
  // ブロックコメント等の継続を hljs に再構築させるための前方文脈を取り出す。
  // 強制分割(行途中)の継続は既存の行結合ロジックが別途処理する。
  var previousContent = _mmdDocument.content();
  var highlightContext =
    _mmdChunkTail.endedWithNewline() && previousContent
      ? lastLines(previousContent, CODE_CHUNK_CONTEXT_LINES)
      : '';
  _mmdDocument.append(text);
  // 追記戦略は「直前の render() が何を描いたか」だけで決める。type や表示モードから
  // 推し直すと render 側と別々に判定が育ち、ソース表示中の Markdown 追記が
  // 描画済み HTML として挟まる形の食い違いになる(TASK-414)。
  //
  // 差分テーブルが画面に出ている間は DOM へ追記しない。通常のソース行
  // (1 本ガター)を混ぜると桁がずれ、行番号の基準も狂う。蓄積は上の
  // _mmdDocument.append で済んでいるため、差分を解除した時点の全体再描画で
  // 追記分もそろって出る。
  if (_mmdRenderedAs === 'diff') {
    return;
  }
  if (_mmdRenderedAs === 'markdown') {
    // Markdown はチャンク境界がブロック境界(コードフェンス外の空行)に揃えられて
    // いるため(StringChunkReader の markdownBlocks)、チャンク単体を描画して
    // 末尾へ足せる。全文を再描画すると巨大ファイルで DOM を作り直すことになり、
    // 段階読み込みの意味がなくなる。
    diagramWrap.insertAdjacentHTML('beforeend', markdownRenderer().render(text));
    _annotatePathRefs();
    // 追記分に ```mermaid フェンスがあれば描画する。render() と違い appendChunk は
    // 同期関数のため await せず、描画済みの図は対象外にする(全図の再描画を避ける)。
    void _mmdRunMermaid(diagramWrap, true);
  } else if (_mmdRenderedAs === 'csv-table') {
    var csvRows = parseCsv(text, lang || ',');
    var tbody = diagramWrap.querySelector('tbody');
    if (!tbody) {
      return;
    }
    // tbody は直前の querySelector で得たものなので、親は必ずその <table>。
    // instanceof で確かめるのは型を絞るためで、成立しない構成は起きない。
    var table = tbody.parentElement;
    if (!(table instanceof HTMLTableElement)) {
      return;
    }
    var headRow = table.tHead && table.tHead.rows[0];
    var minCols = headRow ? headRow.cells.length : 0;
    // 後続チャンクに幅広行があればヘッダを拡張する。
    var maxNewCols = 0;
    for (var r = 0; r < csvRows.length; r++) {
      var csvRow = csvRows[r]!;
      if (csvRow.length > maxNewCols) {
        maxNewCols = csvRow.length;
      }
    }
    if (maxNewCols > minCols && headRow) {
      for (var c = minCols; c < maxNewCols; c++) {
        headRow.insertAdjacentHTML('beforeend', '<th></th>');
      }
      minCols = maxNewCols;
    }
    var firstNew = tbody.rows.length;
    tbody.insertAdjacentHTML('beforeend', csvRowsHtml(csvRows, minCols));
    for (var r2 = firstNew; r2 < tbody.rows.length; r2++) {
      _walkTextNodes(tbody.rows[r2]!, false);
    }
  } else {
    // 行番号付きコード表への追記。ソース表示のテキスト種別・コード種別('code')と、
    // CSV/TSV のソース表示('csv-source')がここへ来る。前者と後者は 1 行の
    // 組み立て方だけが違う(CSV は列ごとのレインボー着色)。
    var isCsvSource = _mmdRenderedAs === 'csv-source';
    var codeEl = diagramWrap.querySelector('pre code');
    if (!codeEl) {
      return;
    }
    var inner = isCsvSource
      ? csvSourceInnerHtml(text, lang || ',')
      : codeChunkInnerHtml(hljs, text, lang, highlightContext);
    var codeTable = codeEl.querySelector<HTMLTableElement>('table.code-table');
    if (codeTable) {
      // 強制分割(前チャンクが改行で終わらなかった)の場合、継続行は新しい行では
      // なく前チャンク最終行の続きなので、生成した最初の行分を <tr> ごと追加
      // せず既存の最終行セルへ結合する(行番号の重複を防ぐ)。
      var startLine = codeTable.rows.length + (_mmdChunkTail.endedWithNewline() ? 1 : 0);
      var rowsHtml = buildLineNumberRows(inner, startLine, _mmdViewOptions.lineNumbers());
      if (!_mmdChunkTail.endedWithNewline() && codeTable.rows.length > 0) {
        var pendingRows = document.createElement('tbody');
        pendingRows.innerHTML = rowsHtml;
        var continuationRow = pendingRows.rows[0];
        if (continuationRow) {
          // HTMLCollectionOf に Array.prototype.at は無い（実測: .at(-1) へ
          // 書き換えると「改行で終わらなかったチャンクの続きは前の行に結合される」が落ちる）。
          // oxlint-disable-next-line unicorn/prefer-at
          var lastRow = codeTable.rows[codeTable.rows.length - 1]!;
          var lastContentCell = lastRow.querySelector('.line-content');
          var continuationContentCell = continuationRow.querySelector('.line-content');
          if (lastContentCell && continuationContentCell) {
            lastContentCell.insertAdjacentHTML('beforeend', continuationContentCell.innerHTML);
          }
          continuationRow.remove();
          rowsHtml = pendingRows.innerHTML;
          _walkTextNodes(lastRow, false);
        }
      }
      var firstNewRow = codeTable.rows.length;
      codeTable.insertAdjacentHTML('beforeend', rowsHtml);
      for (var i = firstNewRow; i < codeTable.rows.length; i++) {
        _walkTextNodes(codeTable.rows[i]!, false);
      }
    } else {
      codeEl.insertAdjacentHTML('beforeend', inner);
      _annotatePathRefs();
    }
  }
  _mmdChunkTail.record(text);
  // 追加分のパス参照も解決する。上の各分岐(_annotatePathRefs / _walkTextNodes)が
  // 生成した未分類の参照だけが対象になるため、ここ 1 箇所で全分岐をまかなえる。
  _mmdResolveReferences();
  _mmdFindRefreshAfterRender();
}

export { renderShape, render, appendChunk, _mmdRerenderCurrent };
