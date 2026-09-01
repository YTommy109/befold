---
id: TASK-567
title: PDF のページ送りを連続スクロールへ改める
status: Done
assignee: []
created_date: '2026-08-29 20:27'
updated_date: '2026-08-29 22:31'
labels: []
dependencies: []
priority: high
ordinal: 824000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDF の表示が `.singlePage` + ホイールのページ送り振り替えになっており、スクロールするとページが瞬時に切り替わる。滑らかにスクロールしないため体感が悪い、というユーザー報告があった。

現状は TASK-564.2 で意図して選んだ形で、`PDFSurfaceLayout.configure` の doc コメントに「連続スクロールにすると 2 ページの端が同時に見える位置で止まらないようにする仕掛けを別に作ることになる。`.singlePage` はそもそも 2 ページを同時に描かないので構造で守れる」と理由が残っている。

今回はこの判断を覆し、`.singlePageContinuous` へ改める。「2 ページの端が同時に見えない」という不変条件は、体感の悪さという不利益に見合わないと判断したため（ユーザー判断 / 2026-08-30）。スナップやページ遷移アニメーションのような新しい仕掛けは足さない（不変条件を守るために機構を増やすのは単純化の逆方向）。

影響範囲: `PagingPDFView` のホイール振り替え、`PDFSurfaceLayout.documentFraction` / `restore` の位置換算（ページ番号 + ページ内位置を 0…1 へ畳む形が連続スクロールでも成立するか）、ADR 0009 と `docs/dev/native-app-design.md` の記述。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PDF が連続スクロールで表示され、ホイール・トラックパッドのスクロールがページ境界で止まらず滑らかに繋がる
- [x] #2 ホイールをページ送りへ振り替えていた `PagingPDFView.scrollWheel` の分岐が撤去され、ページ送りのための積算・閾値の状態が残っていない
- [x] #3 `WindowPresentationMemory` による表示位置の記憶・復元が連続スクロールでも往復し、そのことをオフスクリーンのテストが固定している
- [x] #4 回転・ズーム（⌘+ / ⌘- / ⌘0）が連続スクロールでも従来どおり効き、既存の PDF 関連テストが通る
- [x] #5 ADR 0009 に `.singlePage` から連続スクロールへ改めた経緯と理由が追記され、`docs/dev/native-app-design.md` の PDF 表示の記述が実装に追随している
- [x] #6 スペース / Shift+スペースが 1 画面ぶんの滑らかなスクロールになり、送る向きが正しい
- [x] #7 ファイルを切り替える瞬間に、まだ画面に出ている前のファイルの倍率が変わらない
- [x] #8 PDF から離れる瞬間に、見えている PDF の上へ読み込み中のスピナーが重ならない
- [x] #9 切り替え直後の最初の 1 フレームがフィット倍率で描かれる（フィット前の倍率で描いてから縮む過程が見えない）
- [x] #10 フィットは「ページ全体が収まる倍率」で、連続スクロールでも幅基準にならない（`autoScales` を使わず `PDFSurfaceLayout.fitScale` が定義を持ち、文書内で最大のページに合わせる）
- [x] #11 表示位置は 0 が先頭・1 が末尾で、`PDFView` のスクロール座標（下ほど y が小さい）との向きの変換が 1 箇所に集約されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー結果（/review-design / 2026-08-30）

### 方針: 位置の表し方を「ページ番号 + ページ内位置」から「文書全体の 1 本のスクロール」へ単純化する

`.singlePageContinuous` では documentView が全ページ分の高さを持つため、
`verticalScrollRoom` は「文書全体の余地」になる。いまの
`documentFraction = (ページ番号 + ページ内位置) / 総ページ数` はページ内位置が
文書全体の割合に化けるため二重計上で歪む。ページ番号を混ぜる形をやめ、
`contentView.bounds.origin.y / verticalScrollRoom` だけで 0…1 を表す。

これは web 面（1 本のスクロールを 0…1 で表す）と**完全に同じ意味**になり、
`inPageFraction` / `scroll(toInPageFraction:)` / `restore` の `go(to:)` と
ページ数の丸めが丸ごと不要になる（機構が減る）。

### 実装手順

1. `PDFSurfaceLayout.configure` を `.singlePageContinuous` にし、doc コメントの
   「構造で守れる」の段落を、改めた理由（体感を優先し不変条件を捨てた）へ書き換える
2. `documentFraction` / `restore` を上記の単純な形へ置き換え、
   `inPageFraction` / `scroll(toInPageFraction:)` を撤去する
3. `PagingPDFView` からページ送りを撤去する（`hasScrollRoom` /
   `accumulatedDelta` / `pageTurnThreshold` / `scrollWheel` の非 Ctrl 分岐）。
   **Ctrl+ホイールと `magnify` のオーバーライドは残る**ので型自体は消せない。
   実態と名前がずれるので `ZoomingPDFView` へ改名する
4. テストを測り直す（下記）
5. ADR 0009 に経緯を追記し、`docs/dev/native-app-design.md` を追随させる

### テストの手当て（項目 7: 測るものと守るものの一致）

- `PDFSurfaceLayoutTests:46` の `.singlePage` 固定を `.singlePageContinuous` へ
  **書き換えるだけにしない**。撤去した振る舞い（hasScrollRoom / ページ送り）の
  テスト（:86 / :98 / :110 / :154）は削除でよいが、それだけだと守るものが減る
- `documentFraction` / `restore` の往復（:204-220）は**連続スクロール前提で
  期待値を測り直す**。特に :217「幅の違う面へ復元」はページ跨ぎの意味が
  変わるので、期待値を実測で決め直す

### 実装前に確かめること（未確認の前提）

- **復元のタイミング**: `PDFPreviewView.updateNSView` は文書差し替えの直後に
  同期で `restore` を呼ぶ。`.singlePage` では 1 ページ分のレイアウトが早く確定して
  いたが、連続スクロールで全ページを積むとレイアウト確定が遅れ、`verticalScrollRoom`
  が 0 のまま復元が**黙って no-op になる**恐れがある。オフスクリーンで実測し、
  必要なら回転と同じくメインキューへ後から積む
- **回転後の再フィット**: `rotate` の `DispatchQueue.main.async` + `forcingRefit` は
  `.singlePage` での実測（scaleFactorForSizeToFit 0.617→0.495 に scaleFactor が
  追従しない）に基づく。連続スクロールでも同じ挙動かを測り直す

### 該当しなかったチェック項目

- 項目 1（判定の真実の源）: むしろ改善。「スクロールの余地の有無」という
  中身の形での判定（`hasScrollRoom`）が撤去されて無くなる
- 項目 4（新しい状態の表示）: ユーザーへ出す状態は増えない
- 項目 6（高頻度経路）: `currentScrollPosition` の呼ばれ方は変わらない
- 項目 8（非同期の世代管理）: 差し替えの世代管理は `contentRevision` のままで変化なし
- 項目 9（粒度・共有範囲）: 記憶の粒度（窓ごと・ファイルごと）は変えない
- 項目 10（行数・責務）: 実測 PDFSurfaceLayout 169 行 / PagingPDFView 69 行。
  どちらも**減る**見込み。プロトコル準拠・注入クロージャ・stored property は増えず、
  `accumulatedDelta` が 1 つ消える
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-30 / コミット 17385683）

- `PDFSurfaceLayout.configure` を `.singlePageContinuous` へ。ページ送りの振り替えを撤去
- 位置は「スクロール量 / 余地」だけで表す形へ единственный化し、`inPageFraction` /
  `scroll(toInPageFraction:)` / ページ数での丸めを撤去（web の面と同じ式）
- `PagingPDFView` → `ZoomingPDFView` へ改名（ページ送りが無くなり名前が実態とずれたため）

### 実測で分かったこと

- 連続スクロールでは `scaleFactorForSizeToFit` が**幅基準**になる（面 400x500 /
  Letter でページ高 517.65pt = 792 × 400/612）。倍率 1.0 の意味が
  「ページ全体が収まる」→「ページの幅が収まる」へ移った。ADR 0009 と
  native-app-design.md に反映済み
- `displaysPageBreaks = false` は試したが撤回。はみ出しの原因ではなく（原因は幅基準
  フィット）、地の暗い背景が消える副作用のほうが大きい
- 文書を外した面は `underPageBackgroundColor` を描かない。テストは地の色を
  明示してから画素を測る形に変えた
- レビューで挙げた「復元がレイアウト未確定で no-op になる懸念」は起きなかった
  （`restore` → `documentFraction` の往復テストが通る）
- オフスクリーンでは**スクロールしても `currentPage` が更新されない**。位置系の
  検証は `documentFraction` で行う形へ変えた

### 検証

- `swift test`: 1786 件すべて通過（exit=0）
- swiftlint: HEAD ベースラインと差分ゼロ（54 件で同一）
- markdownlint-cli2: 0 issues

### 残り

- AC #1（実機で滑らかにスクロールすること）はユーザーの目視待ち

## 実測で分かったこと（設計の前提が 4 回変わった）

1. **連続スクロールでの `scaleFactorForSizeToFit` は幅基準**（面 400x500 / Letter でページ高 517.65pt = 792 × 400/612）。`scaleFactorForSizeToFit` を override しても `autoScales` はその値を読まない（回転後に幅基準へ戻る）。縦フィットを保つには `autoScales` を捨て、倍率を面が覚えて `layout` で入れ直すしかない
2. **`PDFView` のスクロール座標は下へ行くほど y が小さい**（`documentView.isFlipped == false`。開いた直後 y = 2394.5 = 余地いっぱい、最終ページで y ≈ 0）。当初この向きを取り違え、表示位置の記憶が上下反転していた（スペースキーの送り方向が逆というユーザー報告で発覚）
3. **`document` プロパティを override してはならない。** PDFKit は `visiblePagesChanged:` からバックグラウンドキューで読むため、`@MainActor` 隔離の override は SIGTRAP でアプリごと落ちる（PDFPageAnalyzerV2 の経路 / クラッシュレポート befold-2026-08-30-060318）。`PDFViewDocumentChanged` 通知で受ける
4. **ページの影は 1 フレームあたり約 30ms。** ページ数と無関係（12 ページでも 231 ページでも first 37ms / scroll5 176ms）。60fps の予算 16.7ms を超えるので無効化した。1.15.1 が影ありで速かったのは WebKit プラグインが別プロセスで GPU 合成しているためで、`PDFView` の CPU 描画とは前提が違う（`wantsLayer` は効かない = 39ms のまま）

## ちらつきの原因（見立てが 2 回外れた）

- 1 回目: 面の宛先（`ownsDocument: !showsPDF`）で塞ごうとしたが、その判定も `operating(on:)` と同じ「描画が確定した種別」を読むため、切り替えの瞬間は前のファイル側が宛先のままで効かなかった。撤去
- 2 回目: `PageZoomProjector.desired` の代入時適用をやめ内容更新時にしたが、`updateContent` はホストの状態が変わるたびに呼ばれ、切り替え直後のそれは `.skip` である。そこでも当てていた
- 3 回目（採用）: `UpdatePlan` が `.skip` 以外のときだけ当てる。TASK-270 の契約「準備完了後に倍率が変わったら即適用」を「次に描かれるときに適用」へ改めた（ウィンドウ生成が対象確定より先に走る元のケースは準備完了時の適用でカバーされたまま）

## 破れたら落ちるもの（5 件、いずれも「戻すと落ちる」ことを実測）

- バックグラウンドから `document` を読むテスト → override を戻すとテストプロセスが signal 5 で死ぬ
- 位置の 0 が先頭・1 が末尾であることの検査
- `.skip` では倍率を当てないことの検査 → ガードを外すと applied が 0.5 になって落ちる
- ピンチの認識器が `applyZoom` へ繋がっていることの検査 → 呼び出しを消すと reported.count が 0 になって落ちる
- 倍率が最初の描画より前に決まることの検査

**4 つ目を足した経緯を残す。** プローブの NSLog を正規表現でまとめて消した際、`applyZoom` の呼び出しごと削ってしまい、ピンチが無反応になった。それでも全件通っていたのは、倍率の検証が `applyZoom` を直接呼ぶ形で**入口の配線を通っていなかった**ため。実測できない入口は静かに壊れる。

## 検証

- `swift test` 1796 件通過
- swiftlint は **origin/main と差分ゼロ**（どちらも 54 件、行番号を正規化した一覧が完全一致）
- 型グループの行数は閾値以内（`ZoomingPDFView` 184 行 / `PDFSurfaceLayout` 218 行 / `ViewerContentState` 240 行 / `PDFSurfaceLayoutTests` 368 行。途中 400 行を超えた時点で `PDFSurfacePositionTests.swift` へ分割済み）
- 実機確認（ユーザー）: 連続スクロール・ピンチ・スペースキーの向きと滑らかさ・縦フィット・切替時のちらつき無し・スピナーが重ならないこと

## 残したもの

切り替え時に一瞬の間が残る（1.15.1 と比べて）。原因未特定のため TASK-569 へ切り出した。面の描画自体は PDFKit のほうが速い（231 ページで 7〜8ms 対 WebKit 内蔵プラグイン 49〜122ms）ことは実測済みで、間はその前後の区間にある。

`docs/dev/native-app-design.md` と ADR 0009 は更新済み（表示モード・フィットの意味・スクロール座標の向き・影・`ZoomingPDFView` の責務）。

## 責務レビュー（`responsibility-reviewer`）と対応

指摘 5 件すべてに同じタスク内で対応した（コミット 365ca93d）。

- **換算式の二重化（High）**: 「フィット倍率 × zoom」が `PDFSurfaceLayout.apply` と
  `ZoomingPDFView.keepZoomAfterLayout` の 2 箇所にあった。`expectedScaleFactor(of:zoom:)`
  へ 1 本化し、面の側は差分判定だけを持つ形にした
- **`as?` による無音の分岐（High）**: `apply(zoom:to:)` が `PDFView` を受けて
  `(pdfView as? ZoomingPDFView)?.zoom` と書き分けていた。引数と `PDFViewProxy` の型を
  `ZoomingPDFView` に絞り、`rotate` / `apply(rotation:)` も揃えた
- **関心の混在（Medium）**: スクロール関連が倍率入力と stored property を 1 つも
  共有していなかったので `PDFSurfaceLayout` へ移した。認識器の累積値は
  `MagnificationTracker` へ畳んだ。`ZoomingPDFView` は 184 → 171 行
- **述語の引数（Medium）**: `showsLoadingIndicator(isShowingPDFSurface:)` は View から
  「PDF の面か」を受け取っており判定が 2 箇所にあった。`FileType.rendersFromData` を
  足し、状態型が自分の `fileType` で判定する computed property にした
- **コメントの実装ずれ（Low）**: 倍率 1.0 の定義が同じファイル内で 2 通り書かれていた
  ほか 3 箇所を修正

指摘 6（倍率適用の契機が `ViewerRenderer+ContentUpdate` 側にある）は「増える兆しが
あれば投影側へ寄せる」という提案で、現時点では追える状態との評価だったため対応しない。

## 最終検証

- `swift test` 1796 件通過
- `xcodebuild build -scheme befold` 成功
- swiftlint: **origin/main と差分ゼロ**（`git archive origin/main` を展開して比較。
  どちらも 54 件で、行番号を正規化した一覧が完全一致）
- 型グループ: `PDFSurfaceLayout` 252 / `ViewerContentState` 242 / `ZoomingPDFView` 171 /
  `PDFSurfaceLayoutTests` 368 行（いずれも閾値 400 以内）
- ガードが空振りでないことの実測（戻すと落ちる）: `document` の override → signal 5、
  `.skip` の倍率適用 → applied が 0.5、ピンチの配線 → reported.count が 0、
  スピナーの述語 → PDF の面で true
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF を .singlePage + ホイールのページ送りから .singlePageContinuous へ改め、体感の悪さを理由に「2 ページの端が同時に見えない」不変条件を捨てた。付随して 6 件の不具合を直した——縦フィット（autoScales は連続では幅基準になり、scaleFactorForSizeToFit を override しても読まないため autoScales 自体を廃止）、スクロール向きの取り違え（PDFView の座標は下ほど y が小さい。表示位置の記憶も反転していた）、スペースキーの滑らかなスクロール、切替時に前のファイルの倍率が変わるちらつき（倍率の適用契機を「描き直すときだけ」へ）、PDF から離れる瞬間のスピナーの重なり、切替直後の 1 フレームがフィット前の倍率で描かれる問題。あわせてページの影を無効化した（1 フレームあたり約 30ms でページ数と無関係）。検証は swift test 1796 件通過、swiftlint が origin/main と差分ゼロ、ユーザーによる実機確認（連続スクロール・縦フィット・スペースキー・ちらつき無し・スピナー無し）、および 5 つのガードが「戻すと落ちる」ことの実測。切替時に残る一瞬の間は原因未特定のため TASK-569 へ切り出した。
<!-- SECTION:FINAL_SUMMARY:END -->
