---
id: TASK-926
title: 置き換えられた文書の Mermaid 実行が、新しい文書の表示を遅らせ、古いエラーやスクロール復元を持ち込む
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T11:24:00Z'
updated_date: '2026-11-09T11:50:00Z'
labels:
  - bug
  - viewer
dependencies:
  - TASK-925
references:
  - BefoldApp/viewer-src/mermaid.ts
  - BefoldApp/viewer-src/render.ts
priority: medium
type: bug
ordinal: 891000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`/code-review high`（origin/main...HEAD、af91627c と 11c0df3e）の指摘。コードを読んだだけの未検証の主張で、再現は未実施。優先度は暫定で、実測後に決め直す。

TASK-925 で `_mmdRunMermaid` を `_mermaidRunTail` で直列化した。対象の要素は呼び出し時に選ぶが、順番が来たときに現在の文書のものかを確かめず、`render` の続きにも自分が最新かの確認がない。要素が DOM から外れていても `mermaid.run` は走る（mermaid.ts の `_mmdRenderAndWrap` はコードで確認済み）。Swift 側は `render` を待たずに送るので、重なりは起きうる。

未検証の主張:
- 図 30 個で各 200ms の文書を 2 秒ごとに再描画すると、古い実行が終わるまで最新の文書の描画が始まらず、遅れが積み上がる。修正前は mermaid のキューで図 1 個ずつ交互に進んでいた
- 古い実行の parseError が新しい render の後に届き、`#mmd-error` を出して `#diagram-wrap` を隠す。修正済みの .mmd がエラー表示のまま残り、隠れた状態で包むと naturalHeight が 0 になる
- 古い render の続きが新しい文書の復元位置を消費し、描画前の短いページで切り詰める。検索の更新と行の表示も描画途中の DOM に走る。確認の欠落自体は TASK-925 より前からあるが、直列化で毎回この順になる
- `viewer-main-markdown-append.test.ts` の「render が重なる」テストは最新の図の実行回数しか見ないので、これらの回帰では落ちない

指摘の修正案（未評価）: 順番が来たときに `isConnected` で絞って全滅ならスキップ、`render` に世代カウンタを持たせて古い続きを打ち切る。CLAUDE.md の単純化の検討を先に行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 上記の各主張について、実 WKWebView での再現結果が測定条件とともに Notes に記録されている。再現しなかったものはその旨が書かれている
- [x] #2 最新の文書の描画が古い実行の積み上がりで遅れるかどうかの実測が Notes にある。遅れない場合は、古い図の描画を止めない根拠も書かれている
- [x] #3 再現した場合、古い実行のパースエラーが最新の文書のエラー表示と表示状態を変えない
- [x] #4 再現した場合、古い render の続きが最新の文書の復元位置を消費しない
- [x] #5 修正した挙動ごとに、修正を戻すと落ちる回帰テストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. /review-design を回す（方針変更なし）
2. mermaid.parseError の代入をやめ、mermaid.run の reject を実行ごとに受け、自分の図が DOM にあるときだけ _mmdMermaidParseError を呼ぶ（ロード失敗は従来どおり無表示）
3. render に世代カウンタを持たせ、await 後に古ければ後処理せず戻る
4. 回帰テストを足し、修正を戻して落ちることを確かめる
5. バンドル再生成、同じハーネスで測り直す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
再現の実測（2026-11-09、実 WKWebView 1200x800、実 mermaid.min.js、修正前=af91627c のバンドル / 修正後=11c0df3e のバンドル、各条件 3 回で 3 回とも同じ傾向。図 1 個の描画は 8 エッジ 22ms / 60 エッジ 84ms / 120 エッジ 161ms）。

ロード済みの mermaid は描画中に macrotask を回さない（図 30 個の実行中、次の render を置いた setTimeout は実行完了まで発火しない）。別タスクで届く render は前の実行に割り込めないので、重なりは (a) mermaid.min.js のロード待ち (b) ラベルの画像読み込み待ち でしか起きない。TASK-925 の Notes と同じ窓。

- 遅れの積み上がり: 再現せず。30 図 x 150 エッジ、ロード済みで 2 秒 / 0.5 秒間隔の render は、修正前後とも各 render が約 9.5 秒で独立に完了（重ならない）。ロード待ちで 2 回重ねても、修正前後とも最新の完了まで約 10.2 秒（単独 9.5 秒との差は約 7%）。DOM から外れた図の描画は安い。レビューの「修正前より悪化」も「積み上がる」も実測と食い違う。
- 古いパースエラー: 再現、ただし修正前後で同じ。.mmd の壊れた文書 → 正常な文書を間隔 0 / 5ms（ロード待ち）で送ると、エラー表示のまま diagram-wrap が none、naturalHeight 0。間隔 20 / 60ms は再現せず。画像待ちの窓では、md で壊れた図を含む文書の 30ms 後に正常な文書を送るとエラーが残る。
- スクロール復元: 再現、ただし修正前後で同じ。間隔 0 / 5ms（ロード待ち）と画像待ち（30ms）で目標 3000 が 0 になる。間隔 20 / 60ms と重ならない対照は 3000。
- テストの穴: 「render が重なる」テストはこの 2 つの回帰で落ちない。

未確認: 実アプリでこの間隔の render が連続する経路（ロード待ちの窓は 20ms 未満、ただし file:// の画像は TASK-925 の Notes のとおり実アプリでは読めない可能性がある）。

単純化の検討: isConnected で古い実行を飛ばす案は採らない。積み上がりが再現せず、実行中の古い実行のエラー（画像待ち）を止められないため。

修正後の実測（同じハーネス、3 回とも同じ結果）: 間隔 0 / 5ms のエラーは表示なし・wrap block・naturalHeight 697、間隔 0 / 5ms のスクロールは 3000、画像待ちのエラーは表示なし、画像待ちのスクロールは 3000。対照（重ならない .mmd / md / 追記の壊れた図のエラー表示、修正後の文書でエラーが消える）は修正前と同一の結果で、本物の mermaid でも reject 経由で表示される。ロード待ちで 2 回重ねた 30 図 x 150 エッジは 10.6 秒（修正前 10.2 秒）で、別の実行順で測った対照の 9.9 秒も修正前の 9.6 秒より遅い。差は測定のばらつきの可能性があるが未切り分け。

受け入れ条件 2（古い図を描画しない）は「再現した場合」の条件で、積み上がりは再現しなかったので適用外とした。古い文書の図は今も描画する（無駄は約 7%）。

回帰テスト（viewer-main-markdown-append.test.ts）を修正を戻して確認: isConnected の判定を外す / parseError の代入を戻す → パースエラーの 2 件が落ちる。世代の確認を外す → 復元位置の 2 件が落ちる。

検証: Jest 23 スイート 767 件、typecheck / lint / format:check、swift test（--skip Integration --skip FileWatcherTests --skip PDF）1897 件 + 77 件が成功、known issue 1 件。PDF 系と xcodebuild は未実行（Swift の差分なし、ファイルの追加なし）。

残る弱点: 内部再描画どうしがロード待ちの窓で重なると、後の render の fallback は描画前の短いページの scrollTop（0 になりうる）を拾う。受け入れ条件の外で、未測定。

未確認: 実アプリでこの窓に render が連続する経路（ハーネスは setTimeout の間隔で代用。evaluateJavaScript の経路では測っていない）。

docs/dev への反映は不要（docs/dev と docs/adr に parseError の記述なし、構成・表示仕様の変更なし）。

訂正: 上の「docs/dev と docs/adr に parseError の記述なし」は誤り。docs/dev/viewer-ui.md の「通知表示」に mermaid.parseError の記述があったので、reject から表示する形に更新した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
レビューの主張を実測して、実在した 2 つの不具合を直した。置き換えられた文書のパースエラーが新しい文書に残る問題と、スクロール復元位置が失われる問題で、どちらも mermaid のロード待ちと画像待ちの窓で修正前後とも再現し、修正後は 0 回。遅れの積み上がりは再現せず、TASK-925 の回帰でもなかったので対応していない（isConnected による実行のスキップは不採用）。エラーは mermaid.run の reject を実行ごとに受け、図が DOM に残るときだけ表示する。render は世代を持ち、古い続きの後処理を打ち切る。回帰テストは修正を戻すと落ちることを確認済み。実アプリの evaluateJavaScript 経路での発生頻度は未確認。
<!-- SECTION:FINAL_SUMMARY:END -->
