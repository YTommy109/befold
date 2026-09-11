---
id: TASK-596
title: XSL を伴う XML を XSLT 変換してプレビューする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-09-08 11:42'
updated_date: '2026-09-09 08:39'
labels: []
dependencies: []
ordinal: 849000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
e-Gov 電子申請の公文書ビューア (https://shinsei.e-gov.go.jp/recept/official-doc-view/) を befold で置き換えたいという要望があった。公文書は .xml と表示用の .xsl (XSLT 1.0) が対で配布され、表示ロジックは XSL 側にある。現状 befold は .xml をソースコードとしてしか開けないため、受け取った公文書を読むには外部サイトへアップロードする必要がある。

WebKit は libxslt 由来の XSLT 1.0 を持つため、xml と xsl を JS の XSLTProcessor に渡す汎用の変換経路を 1 本用意すれば足りる。法令標準XML のようにスタイルシートが同梱されないスキーマは対象外で、TASK 側で別途扱う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 xml-stylesheet 処理命令が指す .xsl を解決して変換に使う
- [x] #2 処理命令が無い場合、同ディレクトリの同名 .xsl をフォールバックとして探す
- [x] #3 xsl が見つからない .xml は従来どおりソースコード表示にフォールバックする
- [x] #4 変換結果の HTML は既存のサニタイズ経路 (DOMPurify) を通してから差し込む
- [x] #5 WKWebView 上で XSLTProcessor が動作することを実測で確認し、結果をタスクの Notes に残す
- [x] #6 xsl または xml が不正な場合にエラーを表示し、クラッシュ・無限ロードしない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileType に `.xsl` / `.xslt` 拡張子を codeExtensionLanguages へ追加（言語は "xml"）。スタイルシート単体をソース表示で開けるようにする。`.xml` は `.code(language: "xml")` のまま据え置き（capabilities・表示モード・チャンク可否を一切変えないため）。
2. FileType に `case xslt` を追加する。**typeByExtension には載せない**ので `FileType(url:)` は決してこれを返さない。描画リクエストの中だけに現れる「変換して描く形」を表す値で、jsValue は "xslt"。7 つの網羅 switch に答える。
3. BefoldKit に `XSLStylesheetResolver` を新設する。`FileReading` 経由で、(a) `<?xml-stylesheet ... href="..."?>` 処理命令の href（同一ディレクトリの相対パスのみ）、(b) 無ければ同名 `.xsl` を探し、見つかれば本文を返す。AC#1/#2。
4. `RenderableContent.make` の戻り値を `(content: String, fileType: FileType)` に変える。`!isSourceMode` かつ `fileType == .code(language: "xml")` かつ filePath あり・切り詰めなし・ホストが兄弟ファイル読み込みを許す（rendererFeatures.embedImages）ときだけ、xsl を解決して `{"xml":…, "xsl":…}` の JSON を content にし fileType を `.xslt` へ昇格する。解決できなければ従来どおり素通し（AC#3）。
5. `ViewerScriptDispatcher.applyRender` / `applyAppend` を戻り値の fileType を使う形に直す（`request.truncation.isTruncated` を make へ渡す）。
6. viewer-src: `renderShape` に "xslt" を通す。`renderers.ts` に `_renderXslt` を足し、JSON を解いて `XSLTProcessor` で変換 → `sanitizeRenderedHtml(DOMPurify, …)` → innerHTML（AC#4）。パース／変換失敗は `#mmd-error` に出し、本文はソース表示へ落とす（AC#6）。BODY_CLASSES に "xslt-body" を追加。
7. テスト: XSLStylesheetResolver（PI あり／PI なしで同名 xsl／どちらも無い）、FileType の新拡張子と `.xslt` の各述語、RenderableContent の昇格条件、JS 側の renderShape と `_renderXslt`（正常・不正 xml・不正 xsl）。viewer-bundle の再生成と ViewerBridgeContractTests の登録も行う。
8. `/review-design` を回してから実装に入る。

9. **/review-design の結果（実装前に確定した設計判断）**
   - 昇格した `.xslt` を `RenderedStateMirror` へ記録しない。`ContentUpdatePlanner.plan` はミラーの丸ごと比較で再描画要否を決めるため、記録すると次回入力の `.code(language:"xml")` と毎回不一致になり全描画がフル再描画になる。ミラーへは `request.fileType` を記録し、昇格は `ViewerBridge.renderScript` の引数だけに閉じる。
   - 上を守らせる担保として「XSLT 描画の直後に同じ入力が来たら `.skip` になる」テストを同タスク内に置く。
   - `<?xml-stylesheet?>` の探索範囲はプロローグ（ルート要素の開始タグより前）に限る。本文全体を文字列一致するとコメント／CDATA 内の同形に当たる。
   - xsl 不在は無言でコード表示（AC#3）。xsl はあるが xml/xsl が不正な場合は `#mmd-error` に出して本文はソース表示へ落とす（AC#6）。
   - .xsl の変更は FileWatcher が監視しないため再描画されない。本タスクの AC 外の制限として Notes に残す。
   - 兄弟 .xsl の読み込みにキャッシュを持たせない（描画頻度が低く、読みは withBlockingWork 内）。`ponytail:` コメントで上限を明記する。
   - 型グループ行数の実測（閾値 400）: FileType 215 / ViewerScriptDispatcher 169 / RenderableContent 17。追加後も余裕があり、新設型は XSLStylesheetResolver のみ。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### AC#5 実測: WKWebView 上の XSLTProcessor

macOS 25.6.0 / システム WebKit の WKWebView（空 HTML を loadHTMLString して evaluateJavaScript）で確認。

- `typeof XSLTProcessor` → `"function"`
- `importStylesheet` + `transformToFragment`（XSLT 1.0、`xsl:output method="html"`）が成功
- 入力 `<doc><title>こんにちは</title></doc>` → 出力 `<div class="t">こんにちは</div>`（非 ASCII もそのまま通る）

結論: 追加ライブラリの同梱は不要で、JS 側の XSLTProcessor 1 本で変換経路を作れる。

### 実装（設計判断と実測）

**設計**: `.xml` は `FileType.code(language: "xml")` のまま据え置き、`RenderableContent.make` が
描画直前に `.xslt` へ**昇格**する形にした。拡張子だけでは決まらない判定（同ディレクトリの
.xsl があるか）を FileType へ持ち込むと、表示モード・チャンク可否・capabilities・
QuickLook 対象集合まで巻き込むため。昇格は render() の引数だけに閉じ、描画済みミラーへは
記録しない（記録すると `ContentUpdatePlanner` の全体比較が毎回不一致になりフル再描画が
止まらない）。この不変条件は `ViewerRendererXSLTMirrorTests` が担保しており、ミラーへ
`renderable.fileType` を入れると落ちることを実測で確認した。

**変換は JS 側**: Swift は xsl を解決して `{"xml":…, "xsl":…}` の JSON を運ぶだけ。
Foundation の `XMLDocument.object(byApplyingXSLT:)` で Swift 側変換もできるが、
不正入力のエラー表示（AC#6）とサニタイズ（AC#4）が JS 側にあるため、変換も JS に置いて
経路を 1 本にした。

**実機バンドルでの実測**（`.build/xcode` の befold.app 内 BefoldKit.framework の
viewer.html を WKWebView へロードして `render(payload, "xslt")`）:

- 正常系: `#diagram-wrap` は `xslt-body`、出力は `<div class="notice"><h1>電子申請の受付通知</h1><p>…</p></div>`。
  xsl に仕込んだ `<script>alert(1)</script>` は DOMPurify で除去され、出力に残らない（AC#4）
- 不正な XML: `#mmd-error` に libxml のメッセージが出て、本文は `hljs language-xml` の
  行番号付きソース表示へ落ちる。クラッシュも無限ロードも起きない（AC#6）

**制限（AC 外）**: FileWatcher は .xml だけを監視するため、.xsl を編集しても再描画されない。
必要なら別タスクで扱う。

**検査**: swift test 1846 件通過 / jest 641 件通過 / oxlint（type-aware）0 件 /
swiftlint は main とのベースライン差分ゼロ（真の新規・解消ともに空）/ xcodebuild 成功。

### 責務レビュー（responsibility-reviewer）の指摘と対応

実装後に 1 回起動し、8 件の指摘を受けて**同じタスク内で 5 件を構造で修正した**。

1. **`FileType.xslt` を撤去し、描画形は JS のトークンで運ぶ形へ変えた（最重要）**
   当初は `FileType` に `case xslt` を足し、「ミラーへ記録しない」を doc コメントと
   `ViewerRendererXSLTMirrorTests` の 1 本で支えていた。指摘のとおりこれは CLAUDE.md の
   「破れない構造」ではなく規約どおりの担保になっていない。`RenderableContent.Renderable` が
   `FileType` ではなく `(type: String, lang: String?)` を持つ形へ変え、`ViewerBridge` に
   `renderScript(content:type:lang:)` を足した。**描画形をミラーへ記録する誤りは型が違うので
   コンパイルエラーになる。** 併せて `FileType` の網羅 switch 6 箇所から「答えを持たない値への
   答え」が消えた。
2. **payload の組み立てを `ViewerXSLTBridge` へ移した。** `{"xml":…,"xsl":…}` は Swift↔JS の
   契約で、`XSLStylesheetResolver`（探索という 1 つの関心）の責務ではない。
3. **言語横断の契約テストを追加した（`ViewerXSLTBridgeContractTests`）。** viewer-bundle.js を
   読んで type トークンと 2 つの JSON キーを照合する。空振りしていないことを実測で確認:
   viewer 側のキー名を `xsl` → `xslSource` に変えると落ちる。
4. **`RendererFeatures.allowsSiblingFileReads` を導出プロパティとして足した。**
   `embedImages`（markdown の画像埋め込み）が XSL 解決の可否まで決めていた。旗は増やさず
   `allowsSpaceScroll` と同じ形で意図を名前にした（QuickLook で無効なのは意図どおり——
   appex は対象ファイル 1 つにしか読み取り権限を持たない）。
5. **`isTruncated:` を `allowsXSLT:` に改めた。** 追記チャンクに `isTruncated: true` を渡して
   「変換させない」を表現していたのは、引数名と値の意味の食い違いだった。

受けなかった指摘: (7)「`make` が種別ごとの前処理の受け皿になり始めている」は引数 7・本体
2 分岐・58 行で、3 つ目の種別を足す時点での切り出しが自然という指摘そのものに同意するが、
いま切ると実装が 1 つの分岐しかない型を生む。(8)「body class を `_mmdSetBodyClasses` 経由に」は
`render()` が分岐前に `_mmdSetBodyClasses(diagramWrap)` で一括除去しており、各分岐が
`classList.add` するのは `_renderHtml` と同じ既存の形なので変えていない。

再検査（リファクタ後）: swift test 1845 件通過 / jest 641 件通過 / oxlint 0 件 /
swiftlint ベースライン差分ゼロ / xcodebuild 成功 / 実機バンドルでの描画も同じ結果。

### 修正: .xml を独立した FileType にした（ツールバーがソース表示に固定される不具合）

**報告**: .xml を開くとツールバーがソース表示になり、レンダリング表示ボタンが押せない。

**原因**: 「拡張子から決まらない判定を FileType に持ち込まない」ために `.xml` を
`.code(language: "xml")` のまま据え置いた設計の帰結。`ViewerCapabilities` は
`canSelectPreviewMode = onDocument && isRenderable` / `canToggleSourceMode = onDocument &&
supportsSourceMode` の 2 つだけを見ており、どちらも `.code` では false になる。
XSLT 変換した内容を出しているのに、ツールバーは「ソース表示・切替不可」と表示していた。

**単純化の検討**: 先に「capabilities 側を per-file にして xsl の有無を見る」案を検討したが、
`ViewerCapabilitiesFactory` は描画のたびに走り、`validateMenuItem` からも引かれる高頻度経路で、
そこへ同期のファイル存在確認を持ち込むことになる。加えて `supportsDiffDisplay` は
`FileType(url:)` から同期で取っており、xsl の有無を見せる先が 2 つに割れる。採らなかった。

**修正**: `FileType` に `case xml` を追加し、`.xml` 拡張子をそこへ移した
（`.plist` / `.xsl` / `.xslt` は `.code(language: "xml")` のまま——XSL を伴わないため
レンダリング切替を生やさない）。`isRenderable` / `supportsSourceMode` が true になり、
表示モードの可否は**種別だけで決め切る**形（ADR 0002 段 2 の導出）に戻った。
`jsValue` は "code"、`codeLanguage` は "xml"、`isChunkable` は true のままなので、
**変換できなかった XML の見え方と、大きな XML のチャンク読み込みは従来どおり**。
「変換できたか」は相変わらず FileType に載せず、`RenderableContent.make` が
render() の type トークンだけを差し替える（この分離は変えていない）。

**実測（GUI）**: 再ビルドした befold.app で sample/sample.xml を開き、System Events で
ツールバーの表示モードを読んだ。修正前は「プレビュー enabled=false / ソース value=1」、
修正後は「プレビュー enabled=true value=1 / ソース enabled=true / 差分 enabled=true」。
（読み込み完了前に読むと修正後でも一時的に前者と同じ値が出るため、着地後に読むこと。）

**回帰の担保**: `FileTypeTests` に「.xml はレンダリング表示とソース表示の切替を持つ」を追加。
`canSelectPreviewMode` / `canToggleSourceMode` が見る 2 つの述語を直接測るので、
`.code` へ戻すと落ちる。

再検査: swift test 1847 件通過 / swiftlint ベースライン差分ゼロ / 型グループ閾値内 /
xcodebuild 成功 / markdownlint・doc citations・doc symbols 0 件。

### sample の 3 パターン

`sample/` に解決経路ごとのサンプルを置いた。実測（`XSLStylesheetResolver.resolve` の
戻り値とツールバーの AX ダンプ）:

| ファイル | 経路 | xsl 解決 | ツールバー |
| --- | --- | --- | --- |
| `sample.xml` + `official.xsl` | 処理命令の href（AC#1） | 1913 文字 | プレビュー(有効/選択) ソース(有効) |
| `same-named.xml` + `same-named.xsl` | 同名フォールバック（AC#2） | 1312 文字 | 同上 |
| `no-stylesheet.xml` | どちらも無し（AC#3） | なし | 同上（変換されずハイライト済みコード） |

`sample.xml` の xsl だけファイル名を `official.xsl` にしてあるのは、同名フォールバックでは
なく処理命令が解決されていることを名前で示すため。`no-stylesheet.xml` は本文の要素内に
`<?xml-stylesheet ... ?>` をエスケープした文字列を含んでおり、プロローグ限定の探索が
本文を拾わないことのサンプルにもなっている。

`same-named.xml` の描画も実機バンドルで確認した（`xslt-body`、エラーなし、
`<style>` は残り `<script>` は DOMPurify で除去）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
XSL スタイルシートを伴う XML を XSLT 変換してプレビューできるようにした。

「同ディレクトリに xsl があるか」は拡張子から決まらないため FileType には持たせず、
描画直前の RenderableContent.make が render() の引数（content と type トークン）だけを
差し替える形にした。Renderable が FileType を持たないので、描画形を描画済みミラーへ
記録する誤りはコンパイルエラーになる。変換自体は viewer 側の XSLTProcessor が行い、
出力は markdown と同じ DOMPurify 経路を通してから差し込む。xsl が無い・xml か xsl が
不正な場合は理由を #mmd-error に出して従来どおりソースコード表示へ落ちる。

XSLStylesheetResolver（探索）・ViewerXSLTBridge（Swift↔JS 契約）・_renderXslt（変換と
サニタイズ）の 3 つに関心を分け、契約は viewer-bundle.js を読む照合テストで固定した。
<!-- SECTION:FINAL_SUMMARY:END -->
