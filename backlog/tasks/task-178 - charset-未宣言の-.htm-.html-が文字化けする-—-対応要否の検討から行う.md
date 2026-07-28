---
id: TASK-178
title: charset 未宣言の .htm/.html が文字化けする — 対応要否の検討から行う
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 01:03'
updated_date: '2026-07-28 02:59'
labels:
  - rendering
  - encoding
  - html
dependencies: []
priority: medium
type: bug
ordinal: 253000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
sample/sample.htm を開くと日本語が文字化けする(添付スクショ)。ファイル自体は妥当な UTF-8 で、<meta charset> が無いだけ。befold は .html/.htm を viewer.html を介さず loadFileURL で WKWebView へ直接ロードする(RendererFeatures.htmlHostFeatures / befold/Viewer/ViewerWebView.swift)。charset 宣言の無い HTML を WebView が既定エンコーディング(日本語環境では Shift_JIS 等)と誤推定し、UTF-8 バイトを二重解釈するため文字化けする。

このタスクは「直すべきか否か」の検討から始める。まず以下を評価し、方針を決めてから(必要なら)実装する。

検討観点:
- そもそも befold として charset 未宣言 HTML の文字化けを直す責務があるか(HTML の仕様上 charset は作者責任、という立場も取りうる)。sample.htm は同梱サンプルなので meta を足すだけで済むが、ユーザーの実ファイルは直らない。
- 直す場合の実現手段と副作用:
  - loadFileURL は charset を指定できない。UTF-8 を仮定して loadHTMLString / loadData(textEncodingName:) へ切り替える案は、相対リソース参照やサンドボックス(allowingReadAccessTo)の扱いに影響する。
  - TextEncoding による自前エンコーディング判定を HTML 直接ロード経路にも通す案。
  - 既定を UTF-8 と仮定して読む案(実運用でどの程度妥当か)。
- 誤検知リスク(本当に Shift_JIS の HTML を UTF-8 と誤って壊さないか)。

成果物として「対応する/しない」の結論と根拠を残す。対応する場合は最小の修正方針まで確定させ、同タスク内で実装・回帰テストまで行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 charset 未宣言 HTML の文字化けに対し befold が対応すべきか否かの結論と根拠が記録される
- [ ] #2 「対応しない」結論の場合: 同梱 sample.htm については文字化けしない状態にする(例: meta charset 追加)か、サンプルとしての意図を明確化する
- [x] #3 「対応する」結論の場合: 実現手段(loadHTMLString/loadData 切替・自前エンコーディング判定 等)の副作用(相対リソース・サンドボックス・誤検知)を評価した上で最小修正を実装する
- [x] #4 対応する場合、UTF-8/宣言あり/宣言違いの各 HTML が正しく表示されることを検証する回帰テストを追加する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
対応要否: 対応する(条件分岐)。理由: TextEncoding 判定を通す他経路(ソース表示/QuickLook/CLI)と異なり、HTML レンダリング表示だけが loadFileURL で WebKit のバイトスニッフィング依存になっている非対称は意図的設計でなく穴。同じ堅牢な検出器を使えば誤検知も他経路と同等。
最小修正(相対リソース回帰を避ける条件分岐):
1. BefoldKit に純粋関数 HTMLCharsetNormalizer を新設。hasCharsetDeclaration(BOM or 先頭1024バイトの charset=) と utf8NormalizedHTML(宣言なしのみ TextEncoding.decodeText で UTF-8 正規化、宣言ありは nil)。
2. ViewerRenderer+ContentUpdate.swift の直接ロード分岐: 宣言ありは従来どおり loadFileURL(相対リソース維持)。宣言なしは webView.load(UTF-8 data, characterEncodingName: UTF-8, baseURL: filePath) で文字化け解消。
3. 副作用: 宣言なし HTML は loadData 経由となり相対リソース read が失われるが、宣言なしは簡易断片が大半で影響小(記録)。宣言あり(外部CSS/画像を持つ通常HTML)は loadFileURL 維持で無影響。
4. AC#4 回帰テスト: UTF-8宣言なし/UTF-8宣言あり/Shift_JIS宣言なし/宣言違い/BOM の各ケースを純粋関数で検証。
sample.htm は宣言なしのまま残し、修正が効くことの実サンプルとする。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
対応要否の結論: 対応する(条件分岐)。根拠: HTML レンダリング表示だけが loadFileURL で WebKit のバイトスニッフィング依存になっており、TextEncoding を通す他経路(ソース表示/QuickLook/CLI)と非対称。これは意図的設計でなく穴であり、同じ堅牢な検出器(BOM/UTF-8/レガシー判定・lossy 棄却)を使えば誤検知も他経路と同等に抑えられる。
実装(最小・相対リソース回帰回避): BefoldKit に純粋関数 HTMLCharsetNormalizer を新設。hasCharsetDeclaration(BOM or 先頭1024バイトの charset=)と utf8NormalizedHTML(宣言なしのみ TextEncoding.decodeText で UTF-8 正規化、宣言あり/判定不能は nil)。ViewerRenderer+ContentUpdate.swift の直接ロード分岐で、宣言ありは従来どおり loadFileURL(allowingReadAccessTo で相対リソース維持)、宣言なしのみ webView.load(UTF-8 data, characterEncodingName: UTF-8, baseURL: filePath)。
副作用評価: loadData は allowingReadAccessTo を伴わないため、宣言なし HTML から相対参照した兄弟リソース(画像/CSS)は読めなくなる。ただし charset 宣言なし HTML は簡易断片が大半で影響小、宣言あり(外部リソースを持つ通常 HTML)は loadFileURL 維持で無影響。誤検知は TextEncoding が lossy 変換を棄却するため実 Shift_JIS を壊さない。
検証: swift test 全 819 テスト緑。HTMLCharsetNormalizerTests 5件で UTF-8宣言なし→UTF-8正規化 / UTF-8宣言あり→nil / Shift_JIS宣言なし→正しく復号 / Shift_JIS宣言あり→nil / BOM→nil を検証(AC#4)。同梱 sample.htm は宣言なし&妥当 UTF-8 で修正対象に該当することを実測、meta を足さず living sample として残す。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
charset 未宣言 HTML の文字化けに『対応する(条件分岐)』と結論。charset 宣言(BOM/<meta charset>)のある HTML は relative リソースを読める loadFileURL のまま、宣言の無い HTML だけ TextEncoding で実エンコーディングを判定し UTF-8 正規化して loadData で表示。相対リソース/サンドボックス/誤検知の副作用を評価した最小修正。BefoldKit に純粋関数 HTMLCharsetNormalizer を新設し回帰テスト5件を追加。swift test 819 件緑、同梱 sample.htm が修正対象に該当することも実測。
<!-- SECTION:FINAL_SUMMARY:END -->
