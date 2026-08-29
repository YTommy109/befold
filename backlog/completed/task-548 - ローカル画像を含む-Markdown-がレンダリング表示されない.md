---
id: TASK-548
title: ローカル画像を含む Markdown がレンダリング表示されない
status: Done
assignee: []
created_date: '2026-08-24 13:13'
updated_date: '2026-08-24 13:47'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 796000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
複数のローカル画像を <img> の属性つきで参照している Markdown を befold で開くと、本文領域が空白のままレンダリングされない。befold プロセスの CPU は 0.0〜0.1% で、待てば描画されるわけではない（60 秒超まで確認）。ユーザーからは「開くのにものすごく時間がかかる」と見える。

## 再現

対象: site/content/medical-expenses.ja.md（本文 6KB、参照画像 4 枚 合計 600KB）。

実測（2026-08-24、インストール済みの befold.app、レンダリング表示）:

| 開いたファイル | 結果 |
| --- | --- |
| site/content/medical-expenses.ja.md | 本文領域が空白のまま 60 秒超、CPU 0.0〜0.1% |
| 同じ本文から <figure> 行だけ削ったもの | 即座に描画（1 秒未満） |
| 同じ画像 4 枚を `<figure><img src alt="x">` だけで並べたもの（本文なし） | 即座に描画 |
| 記事と同じ属性つき <figure> 4 枚（本文なし） | 空白 |

画像のバイト量そのものが原因ではなく、引き金は <img> タグの属性側にある。記事の <img> は
src / alt（長い日本語）/ loading="lazy" / width / height と、<figure class="article-shots"> を持つ。
どの属性が引き金かは未確定（切り分けを試みた回はセッション復元で前のウィンドウが重なり、測定が汚染された）。

## 疑っている経路

befold はローカル画像を Swift 側で読んで base64 の data URI に埋め込んでから WebView へ渡す
（BefoldKit/MarkdownImageEmbedder.swift:52-88）。WKWebView の読み取り許可が同梱 Resources に
限定されているためで（BefoldRenderKit/ViewerWebViewFactory.swift:64-71）、この設計自体は必要なもの。

置換対象は <img> タグの src 属性値だけを正規表現の範囲計算で切り出している
（MarkdownImageEmbedder.swift:150-172）。非 ASCII を含む属性があると範囲がずれる形のバグが
起きうる場所で、壊れた文字列が JSONEncoder → evaluateJavaScript へ渡ると
（BefoldKit/ViewerBridge.swift:118-132）JS のシンタックスエラーで何も描画されない。
CPU が張り付かないまま空白という観測はこの筋と整合する。ただし未確認の仮説であり、
断定せずに実測で確かめること。

## なぜ気づけなかったか

viewer の描画経路には所要時間の計測も失敗の検出も無い（BefoldApp 配下に os_signpost / OSLog /
performance.now は 0 件）。JS 側でエラーが起きても Swift 側は成功として扱い、どこにも出ない。
同型の事故を次に検出できるようにするところまでを本タスクの範囲に含める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 site/content/medical-expenses.ja.md をレンダリング表示で開くと、画像 4 枚を含めて 3 秒以内に描画される
- [x] #2 引き金となった入力条件を実測で特定し、Implementation Notes に再現手順つきで記録する
- [x] #3 修正を戻すと落ちる回帰テストがある（JSC でのみ再現するため、判定は scripts/webview-smoke.swift の所要時間で行う）
- [x] #4 viewer の描画が JS 側のエラーで失敗したことを Swift 側が検出できる（失敗が黙って握り潰されない）。検出手段は ViewerScriptDispatcher に置く
- [x] #5 scripts/webview-smoke.swift が実アプリと同じ読み込み経路で「非 ASCII を含む長い <img> の文書が描画されること」を検証し、失敗時に非ゼロ終了する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 真因（起票時の仮説は外れ）

起票時に疑っていた `MarkdownImageEmbedder` の範囲計算は無関係だった。src の差し替えは
正しく行われている。止まるのは viewer(JS) 側。

`viewer-src/markdown.ts` の `replaceRemoteImages()` が置いていた当たり付けの早期 return
`/<img[^>]+src\s*=\s*["']?\s*https?:/iu` が、JSC で破滅的にバックトラックする。
引き金は **`u` フラグ + 文字列に非 ASCII が 1 文字でも含まれること**。

実測（WKWebView、`<img>` 1 つの中の文字数を変えて `test` を 1 回）:

| 文字数 | 非 ASCII を含む | 全 ASCII |
| --- | --- | --- |
| 24,000 | 379 ms | — |
| 48,000 | 1,512 ms | — |
| 96,000 | 5,991 ms | — |
| 192,000 | 23,666 ms | 1 ms |

文字数の二乗で伸びる。同じ正規表現から `u` を外すと 192,000 字でも 1 ms、`[^>]+` を
`[^>]+?` にしても 1 ms、`/https?:/iu` のようなリテラルは 0 ms。JSC が 16bit 文字列 + `u`
では Yarr JIT に載せられず、`[^>]+` の後戻りを解釈実行するため。

記事（画像 4 枚を data URI 化して 772KB）では 60 秒超まで返らず、本文が空白のまま固まる。
CPU が 0% に見えたのは、回っているのが befold ではなく WebContent ヘルパープロセス
だったため（`sample` で `JSC::regExpProtoFuncTest` → `JSC::RegExpObject::match` に
2500/2500 サンプル、と特定）。

### 再現手順

1. `site/content/medical-expenses.ja.md` の `<img src>` をローカル PNG の data URI へ置換した文字列を作る
2. viewer.html を `loadFileURL` した WKWebView で `await render(doc, 'md')` を呼ぶ
3. 修正前は 60 秒経っても解決しない／修正後は 52 ms で解決する

最小形は `<img src="data:image/png;base64,AAAA" alt="図" + "a"×96000 >` の 1 タグ。
`alt` を `"x"` に変えるだけ（全 ASCII）で 0 ms になる。

## 修正

単純化を先に検討した。早期 return が省いていた DOM の往復は、772KB の文書でも実測 8 ms
しかない。バックトラックしない別の判定式へ置き換えるのではなく、**判定そのものを外して
常に DOMParser 経由の走査へ委ねた**。正規表現で HTML の当たりを付けない形にすれば同型の
停止は再発しない（「同型のバグは構造で塞ぐ」）。

副作用として `replaceRemoteImages` が常に `DOMParser` を要求するようになり、node 環境の
Jest で 12 件が `DOMParser is not defined` で落ちた。テストファイルごとに用意する形は
新しいテストを足したときだけ落ちるので、`__tests__/support/browserGlobals.js` を
`setupFiles` に置いて全 suite で同じ前提にした。

## 黙って握り潰さないための手当て

`ViewerScriptDispatcher` の `evaluateJavaScript` はすべて `completionHandler: nil` で
投げっぱなしだった。`evaluate(_:on:label:)` に集約し、失敗を
`Logger(subsystem: "com.degino.befold", category: "viewer-script")` へ用途つきで残す。

ただし今回のような「JS が返らない」形では completionHandler 自体が呼ばれないため、
これでは検出できない。その形は `scripts/webview-smoke.swift` に足した
`checkLargeNonASCIIDocumentRenders`（所要時間 3 秒で判定）が受け持つ。

## 検証

- 修正前の bundle で `swift scripts/webview-smoke.swift` → `FAIL: 非 ASCII を含む長い <img> の描画に 5s かかった(退行)`（5,957 ms）で非ゼロ終了
- 修正後 → 4 ms で PASS
- 記事そのもの（772KB・画像 4 枚）の `render` 所要時間: 52 ms
- `npx jest`: 568 passed / 12 suites
- `swift test`: 1701 tests / 270 suites passed
- `npm run lint` / `format:check` / `typecheck:viewer`: 指摘なし
- swiftlint: origin/main とのベースライン差分ゼロ（54 件で一致）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer の replaceRemoteImages が置いていた当たり付けの正規表現 /<img[^>]+src\s*=\s*["']?\s*https?:/iu が、非 ASCII を含む長い文書で JSC の破滅的バックトラックを起こし、描画が返らなくなっていた（文字数の二乗。192,000 字で 23.6 秒、全 ASCII なら 1ms）。省ける DOM の往復は 772KB でも 8ms しかないため、判定式を差し替えるのではなく判定そのものを外して常に DOMParser 経由の走査へ委ねた。あわせて ViewerScriptDispatcher の evaluateJavaScript を 1 箇所へ集約して失敗を OSLog へ残し、返らない形は scripts/webview-smoke.swift の所要時間アサートで検出する。記事の描画は 60 秒超 → 52ms。swift test 1701 件・jest 568 件・swiftlint ベースライン差分ゼロで確認。
<!-- SECTION:FINAL_SUMMARY:END -->
