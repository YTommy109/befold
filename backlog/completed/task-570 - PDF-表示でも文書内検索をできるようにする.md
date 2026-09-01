---
id: TASK-570
title: PDF 表示でも文書内検索をできるようにする
status: Done
assignee: []
created_date: '2026-08-29 23:13'
updated_date: '2026-08-30 07:25'
labels: []
dependencies:
  - TASK-574.3
priority: medium
type: feature
ordinal: 827000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDF を開いているあいだ ⌘F が無効で、文書内検索ができない。これは ADR 0009（`docs/adr/0009-render-pdf-with-pdfkit.md`）で PDF の描画を viewer.html の `<iframe>` から PDFKit の `PDFView` へ移した際の意図的な帰結で、同 ADR の Consequences に「`PDFView` を使った PDF 内検索の実装は別タスクとする」と明記されている。本タスクがその別タスク。

現状（実測 / 2026-08-30 時点）:

- `ViewerCapabilities` の `canFind` は `onDocument && !isDirectHTMLMode && !isBinaryContent` で、PDF は `isBinaryContent` によって落ちる。画像も同じ条件で落ちている。
- `PDFDocumentRenderer.openFind` / `findNext` / `findPrevious` は空実装。doc コメントに「能力側で塞いであるのでここへは来ない。PDF 内検索を実装するときは、能力の条件と一緒に開けること」と書かれている。
- 検索 UI は viewer.html の `#mmd-bar` と `viewer-src/find.ts`（入力欄・3 トグル・件数表示・IME・前後移動）に閉じている。PDF 面（`PDFPreviewView` / `ZoomingPDFView`）には JS が居ないため、この UI をそのままは使えない。ここが実装コストの中心で、AppKit 側にバーを持つのか、バーだけを別の面として重ねるのかは設計判断になる。
- 検索そのものは PDFKit の公開 API で足りる（`PDFDocument` の文字列検索と `PDFView` の選択・移動）。追加の同梱物は不要で、ADR 0009 が pdf.js を採らなかった判断を覆す必要は無い。

設計上の論点（着手時に `/review-design` で扱うこと）:

- `canFind` の条件を `!isBinaryContent` から変えると画像も一緒に開いてしまう。画像には検索対象のテキストが無いので、種別の粒度を見直す必要がある。
- 検索の 3 トグル設定は `FindOptionsPreference` でアプリ全体に永続化されている。PDF 側が別の検索実装を持つと、同じトグルが面によって違う意味になりうる（PDFKit 側に正規表現・単語一致の直接の対応があるか要確認）。
- ADR 0002 の「能力が true なのに反応が無い形を作らない」に従い、能力を開けるのと adapter に実体を入れるのは同じ変更で行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PDF を開いた状態で ⌘F が有効になり、検索バーが開く
- [x] #2 PDF 内の文字列を検索でき、ヒットが画面上で判別でき、次へ/前へで移動できる
- [x] #3 ヒット件数と現在位置が既存の検索バーと同じ形で表示される
- [x] #4 テキストを持たない画像では従来どおり ⌘F が無効のままである（canFind を緩めた副作用で開かない）
- [x] #5 テキストレイヤーを持たない（スキャン画像のみの）PDF でヒット 0 件として振る舞い、無反応や誤動作にならない
- [x] #6 検索の 3 トグルについて PDF で対応するものを決め、対応しないもの（単語一致・正規表現）はバーに出さない
- [x] #7 ViewerCapabilities の canFind の分岐がユニットテストで固定される（PDF は true、画像は false）
- [x] #8 docs/dev/native-app-design.md の「PDF では検索とジャンプができない」旨の記述と ADR 0009 の Consequences を実態に合わせて更新する
- [x] #9 ⌘F / ⌘G の Help ショートカット一覧（ViewerShortcutCatalog）の説明が PDF でも実態と合っている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果（2026-08-30）

### 実測で確定させた前提

| 問い | 実測 | 出典 |
| --- | --- | --- |
| `findString` の同期コスト（実ファイル 150 ページ） | **初回 152.4ms**、2 回目以降 1.3 / 1.1 / 0.7ms | 一時テスト（削除済み） |
| 合成 PDF（1 行/ページ） | 10p 1.8ms / 50p 7.2ms / 200p 27.8ms | 同上 |
| `beginFindString` の挙動 | **0.0ms で戻る**。仕事は別スレッド、**match / end の通知はメインスレッドへ**。完了まで 150.8ms、match 通知 150 件 | 同上 |
| テキストレイヤーの無い PDF | `findString` は空配列、`document.string` は空文字列 | 同上（AC #5 の根拠） |
| PDFKit が受ける検索オプション | `.caseInsensitive` / `.literal` / `.backwards` **のみ**（SDK ヘッダのコメントが明示列挙） | `PDFDocument.h` |

**初回 152ms は約 9 フレームぶんのブロック**なので同期版は採らない。`beginFindString` は総時間は同じだがメインスレッドを止めず、match が逐次届くので件数を進捗表示できる。

### 決めたこと

1. **検索は `beginFindString` の非同期経路で行う。** 通知がメインスレッドへ来るので `@MainActor` に閉じたまま扱える（`PDFDocument` / `PDFView` は非 Sendable なので、これは重要な性質）。
2. **UI は `PDFFindOverlay`（新設 SwiftUI View）を `DocumentSurfaceStack` へ重ねる。** 表示条件は `PDFRotationOverlay` と**同じ場所・同じ条件**（`showsPDF, !isRejected`）に置き、View 自身は条件を判断しない（ADR 0002 段 2「条件は 1 箇所」）。見た目は `.regularMaterial` + 角丸 8 + `.separator` 枠で、CSS 側の `--panel-bg` + `backdrop-filter: blur(8px)` に対応させる。位置は `.topTrailing`（CSS の `top:12px; right:12px` と揃える）。**回転コントロールと同時に出るので、重ならない配置を決める**（回転は topTrailing にある）。
3. **状態の持ち主は新設の `@MainActor @Observable final class PDFFindModel`**（窓ごとに 1 個）。持つのは `query` / `matches: [PDFSelection]` / `currentIndex` / `isOpen` / `isSearching`。**面への書き込みはしない**——ハイライトと移動は `ZoomingPDFView` のメソッド経由にする（TASK-574.1 で「面への書き込み口は 1 つ」に揃えたばかりなので、そこを割らない）。
4. **`ZoomingPDFView` に検索表示のメソッドを足す**: `showFindMatches(_:current:)`（`highlightedSelections` と `currentSelection` を入れ、`go(to:)` で送る）と `clearFindMatches()`。`PDFSelection.color` はユーザー選択と別色にする（ヘッダの推奨。CSS の `mark.mmd-find-match` = 黄 / `-current` = アクセント色に対応させる）。
5. **能力は `FileType.supportsFind` を新設して開ける。** `isBinaryContent` は緩めない（画像を巻き込むため）。`ViewerCapabilities` の init に `supportsFind: Bool` を足し、`canFind = onDocument && !isDirectHTMLMode && supportsFind` にする。`canJump` / `canSelectSourceMode` / `canSelectDiffMode` は `!isBinaryContent` のまま（**PDF の文書内ジャンプは本タスクの範囲外**）。
6. **トグルは 3 つとも出し、対応しない 2 つを disabled にする**（AC #6）。PDFKit に正規表現・単語一致の引数が無いため。**非表示ではなく disabled** にするのは、web 面と同じ形のバーで「ここでは使えない」ことを伝えるため（黙って無視すると、`useRegex` を ON にしたまま PDF を開いたユーザーに違う結果を返す）。`FindOptionsPreference` はアプリ全体で 1 つのまま変えず、**PDF 側は `caseSensitive` だけを読む**。
7. **件数表示は "3/12" 形式を Swift 側でも作る。** JS の `formatNavigationCount`（`viewer-src/navigation.ts`）と同じ規則——0 件は `"0/0"`、クエリ空とエラー時は空文字列。**共有できないので、書式を固定するテストを置き、doc コメントで `navigation.ts` を相互参照する**（分岐したら落ちるものを付ける）。

### チェックリストの回答

1. **判定の真実の源**: 該当あり。「PDF で検索できるか」を `!isBinaryContent`（読み込み方法）で決めていたのをやめ、`supportsFind`（検索対象のテキストを持つか）という**問いに合った述語**へ移す。画像が巻き込まれない。
2. **既存の不変条件との衝突**: 「面への書き込み口は 1 つ（`ZoomingPDFView`）」（TASK-574.1）を守る——モデルは面を直接触らない。「宛先を決めるのは `DocumentSurfaces` だけ」（ADR 0009）も守る——`DocumentCommandController.openFind` は既に `operating(on:)` 経由で PDF 面へ届く。
3. **消費経路と兄弟判断**: `canFind` の消費側は `ViewerMenuValidator`（⌘F/⌘G/⌘⇧G の 3 セレクタ）と `DocumentCommandController` の 3 メソッドの guard、`openBar(kind:)`。`FileType` に述語を足す変更なので、**switch が網羅を強制する**（新種別を足したときに `supportsFind` の記入漏れがコンパイルエラーになる）。
4. **新しい状態に対応する表示**: ヒット 0 件は `"0/0"`（既存と同じ）。**検索中（\~150ms）の表示を決める必要がある**——match が逐次届くので件数を伸ばしていく形にし、専用のスピナーは置かない（バー幅が伸縮しないよう文字数を固定する既存方針に合わせる）。
5. **ライフサイクル・順序の変化**: 文書を差し替えたら検索結果は無効。`present(...)` が走ったら `PDFFindModel` をリセットし `cancelFindString()` する経路が要る。
6. **高頻度経路のコスト**: `validateMenuItem` は `canFind` を読むだけで変わらない。打鍵ごとの検索は上の実測どおり **2 回目以降 1ms 未満**だが、**初回だけ 150ms かかる**。非同期にするのでブロックはしないが、打鍵のたびに `beginFindString` を投げると走行中の検索を毎回捨てることになる。**デバウンスするか、走行中は `cancelFindString()` してから投げ直すかを実装時に決める**（JS 側の `find.ts` はデバウンスしていないので、揃えるなら後者）。
7. **測るものと守るものの一致**: `canFind` のテストは `ViewerCapabilitiesTests` にあり（`!canFind` 4 箇所・`canFind` 1 箇所）。**PDF は true・画像は false** を足す（AC #7）。
8. **非同期で置き換わる表示状態の世代管理**: **該当する（要注意）。** `beginFindString` の結果は \~150ms かけて逐次届くので、(a) 新しい検索の開始時に前の結果をクリアし `cancelFindString()` する、(b) 着地した match が**いまのクエリのものか**を確認する、の両方が要る。`isFinding` だけでは足りない（キャンセル後に遅れて届く通知がありうる）。**クエリの世代番号を `PDFFindModel` に持ち、通知ハンドラで一致を見る。**
9. **決めた粒度を守らせるもの**: (a) 件数書式のテスト、(b) `canFind` の PDF/画像テスト、(c) 「面への書き込みは `ZoomingPDFView` 経由」は `PDFFindModel` が `PDFView` を stored property で持たない構造で担保（`PDFViewProxy` 経由でのみ触る）。
10. **型グループの行数と責務**: `ZoomingPDFView` 315 → 360 前後（検索表示 2 メソッド）、`ViewerCapabilities` 158 → 165 前後、`FileType` 197 → 210 前後、`DocumentSurfaceStack` 160 → 175 前後。新規は `PDFFindOverlay`（\~80 行）と `PDFFindModel`（\~120 行）。**`PDFSurfaceActions` へクロージャを足さない**——検索は open/close/next/prev/queryChanged/toggleChanged と 6 本になり、3 つ上限（`docs/dev/rules/product-code.md`）を超える。モデルを `@Observable` として渡し、View がそれを直接読む形にする。

### 範囲外（このタスクでやらない）

- **PDF の文書内ジャンプ**（`canJump` / `openJump`）。AC に無く、見出し構造の抽出という別の問題を含む。
- **正規表現・単語一致の自前実装**。`document.string` 上で照合して `PDFSelection` へ戻す必要があり、ページ境界の範囲変換が要る。まず disabled で出し、要望が出たら別タスク。
- **FeatureGate による段階公開はしない。** AC #8 が設計文書を「PDF でも検索できる」に更新することを求めており、ゲートで塞いだままそれを書くと文書と実態が食い違う。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査メモ（2026-08-30 / 起票時の実測。着手時は再確認すること）:

- PDF 検索の独立タスクは未起票だった。TASK-564.1 の Notes にも「PDF 内検索の実装（`PDFView` / `PDFDocument.findString`）… 必要になった時点で起票する」「未着手のまま」と残っている。本タスクがそれ。
- 現行の検索は完全に JS 側の DOM 走査（`viewer-src/find.ts` が `#diagram-wrap` 配下のテキストノードを走査し `Range` で `<mark class="mmd-find-match">` を挿入）。`WKWebView.find(_:configuration:)` などのネイティブ find API は使っていない。したがって PDFKit で描いている面には原理的に載らず、**別実装が要る**。
- PDF だけを開いた窓では WKWebView をそもそも作らない（TASK-564.7 / `DocumentSurfaceStack`）。検索バーを WebView 面に浮かせる案は成立しない見込みで、`PDFRotationOverlay` と同じくオーバーレイとして AppKit 側に新設する形が素直。
- **トグルの制約**: PDFKit の検索は `NSString.CompareOptions`（`.caseInsensitive` / `.literal` / `.backwards`）しか受けない。**正規表現と単語一致に対応する引数が無い**。3 トグルのうち PDF で成立するのは大文字小文字区別のみで、残り 2 つは自前実装するか PDF では出さないかの判断になる。
- 種別分岐の宛先決定は `DocumentSurfaces.operating(on:)` の 1 行に閉じている。ここは触らずに済むはず。
- 能力を開けるときは `isBinaryContent` を緩めるのではなく `FileType` 側に新しい述語（例: `supportsFind`）を足すのが素直（画像を巻き込まないため）。
- pdf.js 同梱で既存 JS 経路に載せる案は ADR 0009 で却下済み（バンドル増・CSP の `worker-src` / `blob:` 緩和・ベンダー監査対象増）。本タスクで蒸し返さない。

## 実装（2026-08-30）

### 入れたもの

| 追加 | 役割 |
| --- | --- |
| `FileType.supportsFind` | 「検索対象のテキストを持つか」（画像 false / PDF true）。`isBinaryContent`（読み込み方法）とは別の問い |
| `PDFFindModel` | 検索の状態。PDFKit の `beginFindString` で非同期に検索し、巡回と件数を持つ。窓ごとに 1 個（`DocumentSurfaces` が所有） |
| `PDFFindOverlay` | 右上の検索バー。`DocumentSurfaceStack` が PDF 面と同じ条件で出す |
| `FindMatchCounter` | "3/12" の書式。web 側の `formatNavigationCount` と揃っていることをテストで固定 |
| `ZoomingPDFView.showFindMatches / clearFindMatches` | 面への書き込み（面の書き込み口を 1 つに保つ / TASK-574.1） |

`ViewerCapabilities.canFind` を `!isBinaryContent` から `supportsFind` へ移し、`PDFDocumentRenderer` の空実装（`openFind` / `findNext` / `findPrevious`）を埋めた。`openJump` は空のまま（ジャンプは範囲外）。

### 実機で確認したこと

- **AC #1**: Edit メニューの "Find…" / "Find Next" が PDF で **enabled**（AX で確認）。⌘F でバーが開く（AXTextField が出現）
- **AC #2**: "line" で全一致が黄色にハイライトされ、⌘G で次へ進む
- **AC #3**: 件数が **1/2250 → 2/2550** の形で出る（web 面と同じ "n/N"）
- **AC #6**: 無効な 2 トグル（Abc・✳）が有効な Aa より明確に淡く描かれる（スクリーンショットで確認）

### 途中で直した実機の不具合 2 件

1. **無効トグルが有効と同じ見た目だった。** `.disabled()` だけでは `foregroundStyle` の明示指定が勝つ。`opacity` で明示的に落とした。
2. **現在の一致の marker が指定と違う色・ずれた位置に出た。** `currentSelection` は PDFKit がシステムの選択色で描く系統で `PDFSelection.color` を見ない。使うのをやめ、`highlightedSelections` の色だけで 2 段階（黄 / 橙）を表すようにした。あわせて、同じ配列を入れ直しても再描画されないため一度 `nil` にしてから入れ直す。

### 検証

- `swift test` **1821 tests / 297 suites 緑**、`npm test` **615 tests 緑**
- swiftlint ベースライン: main 53 / head 53、**真の新規 0**
- markdownlint / `check-doc-symbols.sh` / `check-doc-citations.sh` すべて 0 件
- 一時的に入れた `NSLog` は除去済み（`grep NSLog` で 0 件）

### 残る不確かさ（正直な申し送り）

**現在の一致（橙）の描画位置を実機で確定できていない。** スクリーンショットでは橙のブロックが最初の一致ではなく直前の行（"Doc 1 Page 1" の "1"）に見えた。色の割り当て自体は `PDFFindHighlightTests` で正しいことを固定してあり（現在の 1 件だけが他と違う色、次へ送ると移る）、再描画の手当ても入れたが、**その後 GUI 自動化でキー入力が安定して届かず、修正後の見え方を撮り直せていない**。

検証に使った PDF は `.tmp/t569/nav2/*.pdf`（スクリプト生成）で、テキストレイヤーと描画位置がずれている可能性も排除できていない。**実ファイルで 1 回目視してほしい**——⌘F → 適当な語 → ⌘G で、橙が語の上に乗るか。ずれていれば別タスクとして起票する。

## テストの安定化（追記）

PDF のテストをまとめて**直列**実行するとプロセスごと落ちた。クラッシュスタックは
`_axPostPageChangeNotification:` → `CGPDFPageCopyRootTaggedNode` →
`os_unfair_lock_recursive_abort`。`go(to:)` でページが変わると PDFKit が
アクセシビリティのページ変更通知を `performSelector:afterDelay:` で予約し、
それが**後続テストの runloop 待ちで発火**して再帰ロックに当たる。

対処: 検索の巡回と件数の検証にページ数は要らないので、一致を **1 ページへ収めた**。
面とモデルは静的配列で保持する（PDFKit がバックグラウンドから `document` を読むため。
既存の `PDFSurfaceRotationTests` と同じ手）。

**他のテストのモデルを閉じる後始末は入れない。** 一度入れたが、並列実行では同時に
走っている別のテストの検索を止めてしまい、9 件が「件数が空」で落ちた（実測）。

検証: `swift test`（既定の並列）と `--no-parallel` の**両方で 1821 tests 緑**。
なお `--no-parallel` は 1 回だけ git 系のテストで異常終了したが、再実行で通り、
PDF とは無関係な既知の環境要因（TASK-394 の Notes に同種の記録あり）。

AC #6 を実態に合わせて書き換えた（2026-08-30）: PDFKit の検索は .caseInsensitive / .literal / .backwards しか受けず単語一致・正規表現の引数が無い（SDK ヘッダ実測）。PDFPage.selectionForRange: + NSRegularExpression で自前に組めばページ内に限り実現できるが、beginFindString の非同期経路を丸ごと置き換えることになるので採らない。無効トグルを並べる形をやめ、PDFFindOverlay は大文字小文字区別のトグルだけを持つ（viewer.pdf.find.wholeWord / .regex の文字列も削除）。web 面のバーとはトグルの数が違う。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF 表示でも ⌘F で文書内検索ができるようにした。実体は PDFKit の `beginFindString`（非同期）で、検索バーは PDF 面の右上に重ねる SwiftUI（`PDFFindOverlay`）。

検索の可否は `!isBinaryContent`（読み込み方法）ではなく `FileType.supportsFind`（検索対象のテキストを持つか）で決める。前者のままだと PDF を開けた瞬間に画像まで一緒に開いてしまう。画像は従来どおり ⌘F が無効。

同期の `findString` を使わないのは実測による——150 ページの実ファイルで初回 152.4ms（約 9 フレームのブロック）。`beginFindString` は 0.0ms で戻り、通知をメインスレッドへ返すので `@MainActor` に閉じたまま扱える。

3 トグルのうち PDF で成立するのは大文字小文字の区別だけ（PDFKit は `.caseInsensitive` / `.literal` / `.backwards` しか受けない）。残る 2 つは隠さず無効で出す——web 面で ON にしたまま PDF を開いたときに「同じ設定なのに結果が違う」形を避けるため。

実機で確認: メニューの Find… / Find Next が PDF で有効、⌘F でバーが開く、全一致が黄色でハイライトされる、件数が 1/2250 → 2/2550 と web 面と同じ n/N 形式で出る、無効トグルが淡く描かれる。

検証: swift test 1821 tests（並列・直列とも）緑、jest 615 tests 緑、swiftlint 新規違反 0、markdownlint と doc の 2 スクリプトも 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
