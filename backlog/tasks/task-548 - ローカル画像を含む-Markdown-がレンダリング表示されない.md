---
id: TASK-548
title: ローカル画像を含む Markdown がレンダリング表示されない
status: To Do
assignee: []
created_date: '2026-08-24 13:13'
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
- [ ] #1 site/content/medical-expenses.ja.md をレンダリング表示で開くと、画像 4 枚を含めて 3 秒以内に描画される
- [ ] #2 引き金となった属性（または条件）を実測で特定し、Implementation Notes に「どの入力で壊れるか」を再現手順つきで記録する
- [ ] #3 修正を戻すと落ちるユニットテストがある（非 ASCII を含む属性を持つ <img> を与えて、src だけが data URI へ置換され他の属性が保たれることを検証する）
- [ ] #4 viewer の描画が JS 側のエラーで失敗したことを Swift 側が検出できる（失敗が黙って握り潰されない）。検出手段は scripts/webview-smoke.swift か ViewerScriptDispatcher のいずれかに置く
- [ ] #5 scripts/webview-smoke.swift が実アプリと同じ読み込み経路で「画像つき Markdown が描画されること」を検証し、失敗時に非ゼロ終了する
<!-- AC:END -->
