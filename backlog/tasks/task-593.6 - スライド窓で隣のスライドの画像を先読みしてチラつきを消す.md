---
id: TASK-593.6
title: スライド窓で隣のスライドの画像を先読みしてチラつきを消す
status: Done
assignee: []
created_date: '2026-09-06 11:42'
updated_date: '2026-09-06 13:38'
labels:
  - slide-mode
  - performance
dependencies: []
parent_task_id: TASK-593
priority: medium
type: bug
ordinal: 864000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スライド窓でファイルを送ると、画像がキャッシュに無い初回だけ「画像がまだ無い状態」が一瞬見える（ユーザー報告 / 2026-09-06）。

## 調査で分かったこと（実測）

- **サンプル側の欠陥ではない。** `<img>` に実寸の `width`/`height` を入れてレイアウトの飛びを消す修正を試したが、**ユーザー確認で「無効。チラつく」**。症状はレイアウトの飛びではなく、画像そのものが間に合っていない状態が見えている。この修正は revert 済み
- **Markdown ではこの問題が起きない。** `MarkdownImageEmbedder` が画像を base64 で本文に埋め込むため画像が HTML と同時に届く。ただし `fileType == .markdown` に限定されている（`ViewerLoadPipeline.swift` と `RenderableContent.swift` の 2 箇所でガード）
- **その手法を HTML へ流用するのは不可。** charset 宣言のある HTML は `loadFileURL(_:allowingReadAccessTo:)` が要り、内容を書き換える `loadData` 経路へ移すと `style.css` などの相対参照が読めなくなる
- **「描画完了まで隠す」機構はコード上どこにも無い**（`ViewerReadinessGate` は viewer.html の JS 実行を保留するもので、画面を隠す機構ではない）
- **先読みは効く（実測）。** 変種ごとに WebView を作り直し、画像も一意名にして測ったところ、表示中のページで `new Image().src` を先に走らせておくと、次のページの解析時点で `complete=true` / `naturalWidth=1200`。先読みなしの対照群は `complete=false` / `naturalWidth=0`

## 方針

案 1（オフスクリーンの二重バッファで `didFinish` まで差し替えない）は、共有の描画経路と `ContentUpdatePlanner` / `RenderedStateMirror` の不変条件に触る一方、効果はスライド窓にしか要らないため採らない（ユーザー合意: 「スライドモードでだけチラつきがなければいい」）。

案 2 = 表示中のページで隣のスライドの画像を先読みする。描画経路には一切触らない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 スライド窓で次/前へ移ったとき、隣のスライドの `<img>` 画像が先読みされている
- [ ] #2 先読みは `.slide` の窓でだけ動き、通常のビューア窓では一切走らない（構造で担保）
- [ ] #3 `<img src>` の抽出が純粋関数としてテストされている（リモート URL・data URI は対象外）
- [ ] #4 隣が現在のファイルと別ディレクトリなら先読みしない（`allowingReadAccessTo` の外は読めないため）
- [ ] #5 同じ画像を繰り返し先読みしない（往復しても再取得が走らない）
- [ ] #6 先読みの失敗は無視され、表示には一切影響しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果（2026-09-06）

### 1. 判定の真実の源（項目 1）

先読みするかどうかは**窓の種別**という事実で決める。「画像があるか」「キャッシュに載っているか」といったデータの状態では決めない。載っているかを調べるより、重複を自前の集合で覚えて二度読まないほうが安い。

### 2. 既存の不変条件との衝突（項目 2）

- **`ViewerReadinessGate` を通さない。** あれは viewer.html の JS 実行を保留する仕組みで、直接 HTML モードでは意味が違う。先読みは表示中のページに対する副作用の無い `new Image()` なので、gate を通すと逆に「保留されたまま流れない」形になる
- **`RenderedStateMirror` / `_mmdViewOptions` に触れない。** 自己完結した IIFE で、グローバルを作らず DOM も変えない
- **`allowingReadAccessTo` の制約を守る。** 現在のファイルのディレクトリ配下しか読めないので、**隣が別ディレクトリなら先読みしない**

### 3. 消費経路の全列挙（項目 3）

スライド窓で表示ファイルが変わる経路は 2 つだけ。

- 窓を開いた直後（`ViewerWindowAssembler.openInitialDocument`）→ 最初のスライドの**隣**を温める
- `moveToAdjacentFile(_:)`（キーによる前後移動。スライド窓の唯一のナビゲーション）

両方から同じ 1 本のメソッドを呼ぶ。`switchFile` 自体には置かない——あれは通常窓と共有で、種別の分岐をあそこへ足すと共有経路に条件が増える。

### 4. 新しい状態に対応する表示（項目 4）

先読みは不可視。**失敗は完全に無視する**（読めない・画像が無い・JS が失敗）。ユーザーへ出す表示は増やさない。

### 5. ライフサイクル・順序（項目 5）

隣のファイルの読み取りは `withBlockingWork` でメインアクター外へ出す。これが自然な遅延になり、表示中のページの読み込みと競合しにくい。

### 6. 高頻度経路のコスト（項目 6）

1 回の移動につき隣 2 つのファイルを読んで正規表現を 1 回かけるだけ。**先読み済みの URL を集合で覚えて重複を避ける**ので、往復しても再取得は走らない。`listSnapshot` はキー 1 回につき 1 度だけ読む（TASK-418）。

### 7. 測るものと守るもの（項目 7）

純粋部分（`<img src>` の抽出・同一ディレクトリ判定）を関数として切り出してテストする。JS の注入自体は GUI 層なので、注入する文字列を組み立てるところまでをテストし、実行はスパイのクロージャで受ける。

### 9. 決めた粒度を守らせるもの（項目 9）

`SlideKeyMonitor` と同じく、**アセンブラが `.slide` のときしか生成しない**。通常窓では prefetcher が nil なので、構造的に走らない。

### 10. 型グループ（項目 10）

`ViewerWindowController` は恒久例外 931 行に張り付いている。stored property 1 つ + 呼び出し 2 箇所で超えるので上限を引き上げる。抽出・組み立ての本体は新しい型へ置き、コントローラには配線だけ残す。

## 実装

- `SlideImagePrefetcher`（新規）: 純粋部分（`imageSources(inHTML:)` / 同一ディレクトリ判定 / JS の組み立て）と、先読み済み集合の保持
- `ViewerWindowAssembler.makeSlidePrefetcher(for:)`: `.slide` のときだけ生成し、`surfaces.web` から JS 実行のクロージャを渡す（窓が proxy を直接覗かない既存の方針を守る）
- `ViewerWindowController.prefetchSlideNeighbours()`: `listSnapshot` を 1 度読み、隣 2 つを prefetcher へ渡すだけ
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 結論: 見送り（2026-09-06、ユーザー判断）

原因の特定には至ったが、有効な修正を作れず、ユーザー判断で打ち切った。
**次に触る人が同じ道を辿らないよう、除外済みの容疑者と再現方法を残す。**

## 症状（再現済み）

スライド窓でファイルを送ると、初回だけ「**スタイルは完全に当たっているが画像だけ未到着で、
そのぶん本文が中央に寄った状態**」が一瞬見える。ユーザーの言葉では
「各スライドの文字列、例えば "QuickLook に対応してます。" が中央に一瞬見える」。
画像のあるスライドでのみ知覚される。

## 実測で除外したもの（すべて「効かない／起きていない」を確認済み）

| 容疑者 | 判定の根拠 |
| --- | --- |
| サンプルの画像サイズ指定（`<img>` の width/height） | ユーザー確認で無効。**ただしハーネスでは確かに枠を確保する**（下記） |
| 隣スライドの画像の先読み | ユーザー確認で無効。先読み自体はキャッシュに載る（対照実験で `complete=true` / `naturalWidth=1200` 対 `false` / `0`） |
| 上記 2 つの同時適用 | ユーザー確認で無効 |
| viewer.html の挟み込み | 実アプリのログで `EXIT direct mode` がスライド間で 0 回 |
| canvas 所有の反転 | 実アプリのログで `drawsBackground=1` 固定 |
| 倍率の再適用 | 実アプリのログで `applyPendingZoom changes=0`（常に 1.0） |
| `allowsContentJavaScript = false` が JS を止めている | ハーネスで `evaluateJavaScript` が動くことを確認（結果 2、エラーなし） |
| WKWebView の地の色 | `underPageBackgroundColor` を変えても中間フレームは変わらず |

## 実アプリでの実測タイミング

`didCommit → didFinish` は画像ありのスライドで 5〜7ms、文字だけで 1〜5ms。
経路（`plan=directHTMLLoad` → `enter` → `loadFileURL`）は全スライドで同一。

## 再現ハーネス（次に調べる人へ）

`takeSnapshot` は Web コンテンツだけを描き**ウィンドウ背景を含まない**ので、
「何も描かれていない」状態は PNG では白になる。画面が白いことの証拠にはならない。
またオフスクリーンの WKWebView は**描画も rAF も走らない**ので、ウィンドウへ載せること。

中間フレームを捉えるには**現象の窓を人工的に広げる**。画像を `sips` で 6000x4000 に
拡大した複製を用意し、実ウィンドウに載せた WebView で A→B を遷移させながら
10ms 間隔で `takeSnapshot` すると、ご報告どおりの中間状態が撮れる。
`<img>` に実寸の width/height を足した変種と比べると、**枠が確保され本文が最終位置に
留まる**ことがフレーム上で確認できる（つまり属性の効果自体は本物）。

## 未解明のまま残っている矛盾

**ハーネスでは width/height 属性が中間状態を明確に改善するのに、実アプリでは
ユーザーの体感が変わらなかった。** ハーネスが再現していないアプリ側の要素
（`DocumentSurfaceStack` の面の opacity 切り替え、SwiftUI の再構成、
`ViewerStore.openFile` → `ContentLoader` → `ViewerRenderer.render` の間の状態）が
残っている。次に着手するならここから。

## 調査の失敗から（同じ轍を踏まないために）

- **最初の測定で「中間フレームは無い」と結論したのは誤り。** サンプリングが 10ms 間隔で、
  現象の窓が 5〜10ms だったため丸ごと飛ばしていた。**サンプリングの粗さを根拠の欠如と
  取り違えない**
- **修正を片方ずつ試して個別に「無効」と判定した。** レイアウトの飛びと画像の遅れは
  別の症状で、単独ではもう片方が残る。**症状が複数あるなら、切り分けの前に組み合わせも試す**
- 「読めない画像」で測ったが、WebKit は壊れた画像として alt の箱を描くため
  「まだ読めていない」とは別物だった
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
見送り。原因は「スタイル適用済み・画像だけ未到着で本文が中央に寄る中間状態」と特定し、ハーネスで再現もできたが、実アプリで有効な修正を作れなかった（画像サイズ指定・先読み・その同時適用がいずれもユーザー確認で無効）。実測で除外した容疑者一覧、実アプリのログ、再現ハーネスの手順、ハーネスと実アプリで結果が食い違うという未解明点を Notes に残した。ユーザー判断で調査を打ち切り、コードへの変更はすべて revert 済み（リポジトリに残した変更は無い）。
<!-- SECTION:FINAL_SUMMARY:END -->
