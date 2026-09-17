# ファイル種別ごとの表示仕様

<!-- derived-from ./native-app-design.md#表示仕様 -->

befold が各ファイル種別をどう描き分けるか（読み込み経路・変換・表示幅）の現在仕様。
操作 UI（ズーム・検索・ジャンプ・表示モード・サイドバー）は
[ビューアの操作 UI](./viewer-ui.md) を参照。描画のデータフローは
[ビューア描画データフロー](./viewer-rendering-dataflow.md) が扱う。

## 種別ごとの扱い

viewer.html・style.css・mermaid 初期化設定は BefoldKit の `Resources/` に同梱する。

- **mermaid 初期化**: `startOnLoad: false`、全ダイアグラム種別 `useMaxWidth: false`、`theme: 'default'`
- **`.mmd` の扱い**: 全文を `<pre class="mermaid">` に渡し mermaid.js に処理させる
- **`.md` の扱い**: markdown-it.js で markdown → HTML 変換する。
  ` ```mermaid ` フェンスは markdown-it のカスタムレンダラーで `<pre class="mermaid">` に出力し mermaid.js が SVG 描画する
- **その他ファイル種別**: SVG / HTML / CSV・TSV / 画像 / 各種ソースコードは
  `FileType` の判定に従い、ソースコードは highlight.js でシンタックスハイライトする
- **印刷・PDF 保存の扱い**: 画面用レイアウトは `body`（`height: 100vh`）の中で
  `.viewer` が `overflow: auto` のスクロールコンテナになる構造のため、そのまま
  印刷すると document が 1 画面分の高さしか持たず、見えている範囲だけで切れる。
  `style.css` の `@media print` が印刷時だけ高さの制約と入れ子の overflow を解き、
  画面に重ねるだけの UI（検索バー・切り詰めバナー・ズームコントロール）を消す
  （TASK-626）。回帰は `scripts/webview-smoke.swift` が実際に PDF を作って
  出た段落数を数えることで見る。

- **`.xml` の扱い**: 同ディレクトリに XSL スタイルシートがあるときだけ XSLT 変換して
  表示する（TASK-596）。スタイルシートの探索は `XSLStylesheetResolver` が担い、
  `<?xml-stylesheet?>` 処理命令の href（プロローグに限る）→ 同名 `.xsl` の順に見て、
  どちらも無ければ従来どおりソースコード表示に落ちる。
  **`.xml` は `FileType.xml`（レンダリング表示を持つ種別）**で、スタイルシートの有無に
  かかわらずレンダリング／ソースの切替を持つ。表示モードの可否は種別だけで決め切る
  （ADR 0002 段 2 の導出。`ViewerCapabilities.canSelectPreviewMode` は
  `isRenderable` しか見ないため、ここを `.code` にするとツールバーがソース表示に
  固定される）。解決できなかった場合のレンダリング表示は、ソース表示と同じ
  ハイライト済みコードになる（`FileType.xml.jsValue == "code"`）。
  `.plist` / `.xsl` / `.xslt` は XSL を伴わないので `.code(language: "xml")` のまま。
  **一方、変換できたかどうかは拡張子から決まらないので `FileType` には載せない。**
  描画直前に `RenderableContent.make` が `{"xml":…, "xsl":…}` の JSON を組み、render() の第 2 引数を
  `ViewerXSLTBridge.renderType` へ差し替える。`RenderableContent.Renderable` が持つのは
  `FileType` ではなく JS のトークン（`type` / `lang` の文字列）なので、
  **描画形を `RenderedStateMirror` へ記録する誤りはコンパイルエラーになる**
  （ミラーは丸ごと比較で再描画要否を決めるため、描画形を記録するとフル再描画が止まらない）。
  Swift↔JS の契約（type トークンと JSON キー）は `ViewerXSLTBridge` が単一の情報源で、
  `ViewerXSLTBridgeContractTests` が viewer-bundle.js を読んで照合する。
  変換そのものは viewer 側の `_renderXslt` が WebKit 同梱の `XSLTProcessor`
  （XSLT 1.0）で行い、出力は markdown と同じ `sanitizeRenderedHtml`（DOMPurify）を
  通してから差し込む。xml か xsl が不正なら `#mmd-error` に理由を出し、原文の
  ソース表示へ落とす。兄弟ファイルを読めないホスト（QuickLook /
  `RendererFeatures.allowsSiblingFileReads` が false）と、追記チャンク・切り詰められた
  内容（構文として閉じておらず必ずパースエラーになる）では差し替えない。
  そのため **XSL を解決できる XML はチャンク読み込みしない**（TASK-608）。
  `.xml` は `FileType.isChunkable` が true で、1000 行（`StringChunkReader.linesPerChunk`）を
  超えると打ち切られるため、放置すると実在の文書では変換経路を一度も通らない
  （実測: e-Gov 法令XMLは最小の日本国憲法 1,476 行でも該当する）。
  判定は `ViewerLoadPipeline.needsWholeDocument` が先頭チャンクを読んだ直後に行い、
  全量読み込み（`.full`）へ切り替える。`FileType.isChunkable` に持たせないのは、
  XSL の有無が拡張子から決まらないため。切り替えるとサイズ上限が 100MB から
  `ViewerLoadPipeline.fullLoadSizeLimit`（本体 20MB / QuickLook 2MB）へ下がるので、
  それを超えるものは切り替えず従来どおり段階描画する——変換はできないが
  `fileTooLarge` の空表示よりソースが読めるほうがよい。
  **本体の 20MB は XSLT 変換に載る XML 専用の上限**（`ContentLoader.maxXMLTransformSizeBytes`、
  TASK-609）。mmd / md / svg / html と共有の 10MB を動かさないのは、そちらが
  mermaid 描画で桁違いに重いため（1MB で WebContent 901MB）。XSLT の出力は素の HTML で、
  実測は 17.0MB の法令XMLで 1.53 秒 / WebContent 686MB。QuickLook を据え置くのは
  appex に 20MB 分のメモリを抱えさせないため。
  **法令標準XML（e-Gov 法令検索の法令XML）だけは、スタイルシートを befold が供給する**
  （TASK-597）。e-Gov は表示用 XSLT を配布しておらず、法令XMLには処理命令も同名 `.xsl` も
  付いてこないため、`XSLStylesheetResolver` の最後の候補として
  `JapaneseLawStylesheet` が同梱の `Resources/japanese-law.xsl` を返す。
  文書に添えられた `.xsl` が常に優先される（利用者が置いたものを内蔵版が上書きしない）。
  判定は **namespace ではできない**——法令標準XMLスキーマ v3 は `targetNamespace` を
  宣言しておらず、ルート要素 `Law` も無名前空間にある。代わりに「ルート要素が `Law` で
  必須属性 `Era` と `Num` を持つ」ことで判定し、走査はルート要素の開始タグに限る。
  XSL は構造とクラス名（`.law-*`）だけを決め、見た目は `style.css` が持つ
  （XSL に `<style>` を埋めると DOMPurify を通るうえ見た目の定義が二重化する）
- **PDF の扱い**: viewer.html を通らない。読み込みは `Data` のまま
  （`ViewerLoadPipeline.Outcome` の `.binary`。base64 化しないのは `PDFView` が
  `Data` を直接受けられるため）運び、`PDFPreviewView` が `PDFView` で描く（ADR 0009）。
  PDF として開けないデータは `RejectReason.damagedDocument` で拒否する
  （読み込みは成功しているため、見なければ黙って空白になる）。
  **PDF でも文書内検索ができる**（TASK-570）。実体は PDFKit の `beginFindString` で、
  可否は `FileType.supportsFind`（画像 false / PDF true）が決める——`!isBinaryContent`
  で判定すると、PDF を開けた瞬間に検索対象のテキストを持たない画像まで一緒に開く。
  ジャンプは見出し構造の抽出が別に要るので `canJump` を `!isBinaryContent` で
  閉じたまま（画像も同様）
- **PDF の見え方**: 全ページを縦に連ねて描き（`.singlePageContinuous`）、
  スクロールはページ境界で止まらず連続する。**`autoScales` は使わない**——連続
  スクロールでの `PDFView` の自動追従は幅基準で、ページの下端が画面外に出る
  （実測: 面 400x500 / Letter でページ高 517.65pt）。倍率は面（`ZoomingPDFView`）が
  「1.0 = フィット」の意味で覚え、ウィンドウのリサイズや回転への追従は
  `ZoomingPDFView.layout` が毎レイアウトで入れ直す。⌘0 で 1.0（フィット）へ戻す。
  当初は 1 ページずつ描いてホイールをページ送りへ振り替えていたが、
  ページが瞬時に切り替わる体感の悪さから連続スクロールへ改めた（TASK-567）。
  ページの影は描かない（連続では全ページ分の影が乗り、描画コストの大半を占める。
  実測: 231 ページで 36.5ms → 4.3ms）。フィットは**ページ全体が収まる倍率**で、文書内でいちばん大きいページに合わせる
  （ページごとに合わせ直すと、スクロール中に倍率が動く）。表示位置は 0 が先頭・
  1 が末尾で、`PDFView` のスクロール座標との向きの変換は
  `PDFSurfaceLayout.scrollOffset(forFraction:in:)` が持つ。
  **スクロール座標の向きは決め打ちせず面に訊く**（`PDFSurfaceLayout.scrollsDownward(in:)`）。
  macOS 26 までは documentView が非反転で下へ行くほど y が小さく、macOS 27 で
  反転した（TASK-628 の実測）。表示位置・送り量・復元位置の 3 つが同じ事実を
  別々のリテラルとして抱えていたため、OS が変わった時点で 3 箇所とも静かに逆を向いた。
  表示位置（文書全体に対する 0…1）と 90 度回転（右上に重ねた `PDFRotationOverlay` の
  2 つのボタン。文書全体に効く）は
  ウィンドウの生存期間だけ記憶する（`WindowPresentationMemory`）。倍率だけは
  内容に依存しないユーザーの意図なので、従来どおり `ZoomStore` で per-file 永続
- **CSV/TSV の数値列**: テーブル表示では列単位に書式を判定する（`viewer-src/csv-columns.ts` の
  `classifyCsvColumn`）。二段構えで、第 1 段「非空セルがすべて数値」を満たす列は右寄せ +
  `tabular-nums`、第 2 段の拒否条件（1,000 以上の値が無い / 先頭ゼロ / 全セル同じ桁数で 4 桁以上 /
  4 桁整数が全部 1900〜2100 / 1 始まりの連番 / ヘッダー名が否定語）をすべてくぐった列だけ
  整数部に桁区切りを入れる。**判定は「外さない」を優先**し、肯定側のヘッダー名マッチ
  （`price` / `金額` 等）は使わない。値そのものは書き換えず、小数部は原文のまま残す。
  判定はヘッダー + 先頭 200 データ行で確定させ、チャンク追記（`render.ts` の `appendChunk`）は
  `document-state.ts` の `_mmdCsvColumns` 経由で同じ判定を再利用する。
  無加工の原文はソース表示（`csv-source`）で見られる
- **CSV/TSV の数値表示の設定**: 桁区切りの有無と負の数の表記（通常 / ▲ / 赤字 / ▲+赤字）を
  設定ウィンドウから選べる（`CsvNumberFormatPreference`。app-global、UserDefaults キーは
  `CsvNumberGrouping` / `CsvNegativeStyle`）。右寄せは設定にせず常時。**どの列が金額かは
  推測せず**、設定そのものが意図を運ぶと考えて、上の第 2 段を通った列すべてに適用する
  （コードとみなされた列には桁区切りも ▲ も赤字も掛からない）。
  変更は `GlobalDisplayBroadcaster.applyCsvNumberFormatToAllWindows` で開いている全窓へ
  即時反映される。コードフォントと違い CSS 変数では表せない（セルの HTML 文字列そのものが
  変わる）ため、viewer 側の `_mmdInitCsvNumberFormat` が現在の文書を描き直す。
  QuickLook 拡張には設定が届かないので、既定（桁区切りオン・通常表記）で描く
- **キャンバス（地）の所有者**: 既定では地の色は `ViewerTheme.canvas`（ウィンドウ背景）が
  唯一の定義で、`WKWebView` は透過・CSS も地を塗らない。これによりネイティブ部分と
  WebView 部分が構成上必ず同色になる。**外部の HTML 文書（`.html` / `.htm` のレンダリング
  表示）だけがこの例外**で、ブラウザと同じく文書が canvas ごと所有する
  （`ViewerWebViewFactory.setDocumentOwnsCanvas`）。透過のままだと、明るい背景を前提に
  文字色だけを指定した HTML がダークキャンバス上に載って読めなくなるため。
  適用先は直接ロード経路（`DirectHTMLModeController` の enter / exit）と、
  viewer.html 内の iframe 経路（QuickLook 等、`OneShotRenderer`）の両方。
  iframe の子文書も子自身の `color-scheme` 宣言に従って WebKit が塗り分けるため、
  CSS 側の手当ては持たない。ソース表示中の HTML は befold がコードとして描くので該当しない

## ファイル種別ごとの表示幅

`#diagram-wrap` は既定で幅 100%。種別ごとの差は `viewer-src/renderers.ts` が
付ける body クラスと `style.css` の規則で決まる。

| 種別 | body クラス | 幅の扱い |
|---|---|---|
| Markdown | `markdown-body` | 読み幅の上限 `980px`。本文内のダイアグラムは左寄せ |
| XSLT 変換した XML | `xslt-body` | Markdown と同じ上限 `980px` |
| CSV / TSV | `markdown-body` + `csv-body` | 上限なし（全幅）。表は内容幅で、広ければ表自身が横スクロールする |
| Mermaid / SVG | なし | 全幅。図はズーム用ラッパー内で中央寄せ（SVG は `max-width: 100%` で幅に収める） |
| HTML | `html-body` | iframe を幅 100% で置き、レイアウトは文書自身が持つ |
| 画像 | `image-body` | 縦横ともウィンドウ内へフィット（寸法は `imageFitSize` が計算） |
| コード・ソース表示 | `code-body` | 全幅。長い行は折り返す（`pre-wrap` + `break-all`） |
| PDF | —（WebView を使わない） | ネイティブの `PDFView` が表示と拡大縮小を持つ |

CSV に `markdown-body` を付けるのは github-markdown-css の表の装飾を借りるためで、
`980px` の読み幅は Markdown 本文のためのもの。そのため CSV の上書きは
`#diagram-wrap.markdown-body.csv-body` として**詳細度で** `markdown-body` の規則に
勝たせ、style.css 内の記述順に依存させない（TASK-633。
`viewer-csv-columns.test.ts` がカスケードを評価して確かめる）。
