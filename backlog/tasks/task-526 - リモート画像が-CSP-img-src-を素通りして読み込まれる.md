---
id: TASK-526
title: リモート画像が CSP img-src を素通りして読み込まれる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-19 03:29'
updated_date: '2026-08-19 04:24'
labels:
  - bug
dependencies: []
priority: high
ordinal: 768000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 事象

Markdown 中のリモート画像（`https://` の shields.io バッジ等）が **実際に読み込まれる**。viewer.html の CSP は `img-src 'self' data:`（BefoldApp/BefoldKit/Resources/viewer.html:17）で、設計上はブロックされる前提だった。TASK-524 の Description も「リモート URL の画像は CSP と『ネットワークへ出ない』設計により表示しない。これは意図した挙動」と書いているが、**この前提は誤り**。

文書を開くだけで外部ホストへリクエストが出る（IP・User-Agent・どの文書をいつ開いたかが相手に渡る）。

## 実測（2026-08-19、TASK-524 の実機確認中）

実アプリと同じ `loadFileURL(_:allowingReadAccessTo:)` 経路で viewer.html を読み、`render(doc, 'md')` した後に計測した使い捨てスクリプトの結果。

入力: `<img src="https://img.shields.io/badge/license-MIT-blue" alt="b">`

```text
complete = 1;
naturalWidth = 78;
src = "https://img.shields.io/badge/l";
violations = ( );
```

- `naturalWidth = 78` は実際に画像バイトを取得してデコードできたことを意味する
- `securitypolicyviolation` イベントは **1 件も発火していない**（CSP がこの取得を検査していない）
- 実 README.md（embedder 適用後）を同じ経路で描画したときも、shields.io バッジ 3 枚が naturalWidth 102 / 99 / 78 で読み込まれた

## 既存のスモークテストが検知できなかった理由

`scripts/webview-smoke.swift` の `checkExfilBlocked` は `<img src="https://..." onload="..." onerror="...">` を入れて `window.__exfil` を見る。しかしインラインイベントハンドラは `script-src 'self'`（'unsafe-inline' 無し）で実行がブロックされるため、**画像が読み込まれても onload が走らない**。結果は 'PENDING' になり、判定は 'LOADED' のときだけ落ちるので通ってしまう。守りたい対象（画像の取得が起きないこと）と測っているもの（インラインハンドラが走ったか）がずれている。

## 未確認

- meta タグの CSP が file:// オリジンで `img-src` に効かないのが WKWebView の仕様なのか、`default-src 'none'` との組み合わせの問題なのかは切り分けていない
- QuickLook 拡張（BefoldQuickLook）と直接 HTML モード（DirectHTMLModeController）でも同じかは未確認
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 スモークテストを naturalWidth（実際に取得できたか）で判定する形へ直し、現状で落ちることを確認する
- [x] #2 リモート画像の取得を実際に止める（WKWebView 側の仕組みで止めるか、meta CSP が効かない原因を特定して直す）
- [x] #3 止めたときのユーザー向けの見え方を決める（黙って壊れた画像にするのか、代替表示を出すのか）
- [ ] #4 QuickLook 拡張と直接 HTML モードでも同じ経路が塞がっていることを確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
レビュー(/review-design)反映後の計画。

1. スモークテスト checkExfilBlocked を naturalWidth 判定へ直す。現行はインラインハンドラ(onload/onerror)を測っており、script-src 'self' で常に不発 = 素通りする(項目7: 測るものと守るものの不一致)。修正前は落ちることを実測で確認する
2. 一次防御(JS): viewer-src の sanitizeRenderedHtml の後段で、DOMParser で切り離した文書上の img[src^=http] を代替表示へ置換する。切り離した文書では画像取得が起きないため、リクエスト自体が発生しない。jsdom テストで担保
3. 二次防御(ネイティブ): 新規型 RemoteLoadBlocker(BefoldRenderKit)が WKContentRuleList(^https?:// と ^wss?:// を block)をコンパイル/キャッシュし、ViewerWebViewFactory.loadViewerHTML がリスト適用後に loadFileURL する。実測: 未適用 naturalWidth=78 / 適用 naturalWidth=0。ViewerWebViewFactory へ足さない理由は責務と行数(現行166行)
   - コンパイル失敗時は fail-open で必ず viewer.html をロードする(ブランクにしない)。マークダウン経路は 1 の JS 層が守る
   - reloadViewerHTML は completion を readiness.run へ積んでから load するため、load の非同期化で取りこぼしは起きない(+RenderHelpers.swift:53-70)
4. 代替表示の文言は ViewerBridge の *StringsScript と同じ形で注入する(Localizable.xcstrings へ追加)
5. QuickLook と直接 HTML モードで実測する。未確認の前提: appex サンドボックスで WKContentRuleListStore が使えるか
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実測

**再現(修正前)**: viewer.html を実アプリと同じ loadFileURL 経路で読み、`<img src="https://img.shields.io/badge/license-MIT-blue">` を render すると naturalWidth=78、securitypolicyviolation は 0 件。meta CSP の img-src は file:// 文書のリモート画像取得を検査しない。script-src / frame-src は同じ宣言で効いているので「CSP が読まれていない」わけではない。

**AC #1**: スモークテストを naturalWidth 判定へ変更。修正を外した状態で `FAIL: 外部画像が実際に取得された(naturalWidth=78)`、戻すと PASS。旧判定(onload/onerror)は script-src 'self' でインラインハンドラが実行されないため常に PENDING で素通りしていた。

**AC #2**: 二層で止めた。
- 一次(JS): replaceRemoteImages() が DOMParser の切り離した文書上で img[src^=http] を置換。リクエスト自体が出ない。jest 11 件 + 既存 550 件 pass
- 二次(ネイティブ): RemoteLoadBlocker の WKContentRuleList(^https?:// / ^wss?://)。probe 実測で naturalWidth 78→0
- url-filter は選択(|)非対応(実測: `^(file|data)://` は 'Disjunctions are not supported yet')。許可列挙はできないため止めるスキームを列挙する形

**AC #3**: 代替表示(.mmd-blocked-image の span、文言は image.blockedRemote / ja「外部画像は読み込みません」、alt をテキスト・元 URL を title に残す)。ユーザー判断。

**AC #4(部分)**: 直接 HTML モードはローカル HTTP サーバへの到達で実測——ルール無しでリクエスト 1 件到達・naturalWidth 1、ルール有りで 0 件・naturalWidth 0。QuickLook は**この非対話セッションでは実測できなかった**(qlmanage -t は befold の appex を使わず OS 既定のテキストサムネイルを返した=生成画像を目視で確認、qlmanage -p はウィンドウを開けず何も起きなかった)。QuickLook は allowDirectHTML=false で直接 HTML モードを持たず、描画は本体と同一の viewer.html + バンドルを同一経路(OneShotRenderer→makeWebView→loadViewerHTML)で通るため一次防御は同じに効く。未確認なのは appex サンドボックスで WKContentRuleListStore が使えるか(fail-open のため使えなくても一次防御は残る)。

**回帰**: swift test の失敗 8 件(ViewerWindowManagerRecentRepositoriesTests)は origin/main を git archive で展開した pristine ツリーでも同一に落ちる既存の問題。単体実行では pass する(並列実行下のみ)。

**ドキュメント**: docs/dev/native-app-design.md に「リモート読み込みの遮断」節を追加。viewer.html と BefoldQuickLook.entitlements の「CSP で外部画像を塞ぐ」という誤った前提を記録したコメントを訂正。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
meta CSP の img-src が file:// 文書のリモート画像取得を検査しない(実測: naturalWidth 78・違反イベント 0 件)ため、遮断を 2 層で実装した。一次は viewer 側 replaceRemoteImages() が DOMParser の切り離した文書上でリモート img を代替表示へ置換し(リクエスト自体が出ない)、二次は RemoteLoadBlocker の WKContentRuleList が ^https?:// / ^wss?:// を block する。適用点は loadViewerHTML の 1 箇所。検証: スモークテストを naturalWidth 判定へ直し修正を外すと FAIL(78)・戻すと PASS、直接 HTML モードはローカル HTTP サーバへの到達がルール有りで 0 件、jest 550 件 pass、swiftlint 新規違反ゼロ。QuickLook の二次防御のみ非対話セッションで実測できず(Notes 参照)。
<!-- SECTION:FINAL_SUMMARY:END -->
