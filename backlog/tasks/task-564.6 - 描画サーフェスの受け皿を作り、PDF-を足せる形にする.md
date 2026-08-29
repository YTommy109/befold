---
id: TASK-564.6
title: 描画サーフェスの受け皿を作り、PDF を足せる形にする
status: In Progress
assignee:
  - '@Tommy109'
created_date: '2026-08-29 10:16'
updated_date: '2026-08-29 10:25'
labels: []
dependencies: []
parent_task_id: TASK-564
priority: high
type: task
ordinal: 821000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 目的

TASK-564.1（PDF を PDFKit の `PDFView` で描く）に着手できる形へ、既存の構造を先に整える。PDF そのものは足さない。

TASK-564.1 の `/review-design` で、PDF 描画の差し替えを既存構造のまま行うと 2 つの型グループが行数上限を即座に超え、かつ ViewerContentView が 4 つ目の関心を抱えることが実測で判明した。構造整理と PDF 追加を同じコミットに混ぜると差分が読めなくなるため、先行タスクとして分離する。

## 実測（2026-08-29 時点）

`scripts/check-type-group-size.sh` の出力より。

- `BefoldApp/befold/App/ViewerWindowController` = **895 行**（`scripts/type-group-exceptions.txt` の例外枠 900 に対し残り 5 行）
- `BefoldApp/befold/Viewer/ViewerStore` = **394 行**（上限 400 に対し残り 6 行）
- `BefoldApp/befold/Viewer/ViewerContentView` = 111 行だが stored `let` が 13 個、`filePreview` が `ViewerWebView` へ渡す引数が 22 個
- `DocumentRendering` のメンバは 1 プロパティ + 12 メソッド。本番で保持するのは `WebViewCommandController` のみ（rg 実測）

行数上限は extension 分割では下がらない（判定は `Foo.swift` + `Foo+*.swift` の合算）ため、責務ごと別の型へ出す必要がある。

## やること

1. **`DocumentSurfaces` を新設**（`befold/App/`）。描画サーフェスの proxy と `DocumentRendering` 実装をまとめて持ち、`ViewerWindowController` の stored property を `webViewProxy` から `surfaces` 1 本へ寄せる。`ViewerWindowController+Capabilities` の `webViewProxy.isDirectHTMLMode` 参照もここ経由へ移す。この時点ではサーフェスは WebView 1 枚のままでよい。

2. **`ViewerContentView` から `DocumentSurfaceStack` を切り出す**（`befold/Viewer/`）。現在の `filePreview` の `ZStack` 全体（`ViewerWebView` + `UnsupportedFileView` + `LoadingIndicatorView` と可視性の導出）を移し、`ViewerContentView` にはフォルダー一覧とファイルプレビューの切替だけを残す。**PDF を足す前に切ること**（後から切ると、22 引数の配線の隣に 2 枚目のサーフェス配線が並んだ状態が既成事実になる）。

3. **`DocumentRendering` を「操作」と「追随」の 2 群へ分ける。** サーフェスが 2 枚になったとき、前者は**振り分ける**もの（zoom / print / find / jump / scroll 位置取得）、後者は**両方へ配る**もの（`applyCodeFont` / `applyCsvNumberFormat` / `applyJumpAvailability` / `noteRename`）。

   後者を振り分けてはならない理由は 2 つある。いずれも既存コードのコメントが名指ししている事故の再発経路。

   - `WebViewCommandController` のコメントが「設定反映を能力で止めると、フォルダーを見ている間の設定変更が常駐 WebView に入らないまま取り残される」と述べている。種別で振り分けると同じ事故が種別の形で戻る。
   - `ViewerWindowController+FileNavigation.handleRename` は `applyURLToWindow(newURL)` を `noteRename` より**先**に呼ぶ。振り分けると `.pdf` → `.md` のリネームで `ViewerRenderer.handleRename` が呼ばれず、`DocumentRendering.noteRename` の doc コメントが警告する TASK-401（スクロール位置の巻き戻り）と TASK-393（旧パスキーへの保存）がそのまま戻る。

4. **`ViewerStore` の余裕を作る。** TASK-564.1 が `ViewerLoadPipeline.Outcome` に PDF 用の Data ケースを足す際、網羅的 switch の受け手が `ViewerStore+Loading` に要る。残り 6 行では入らないため、受け取りを `ViewerContentState`（実測 155 行）側へ寄せる形にしておく。`ViewerContentState` は既に `content` / `contentRevision` / `hasDeclaredHTMLCharset` を持つ「表示中文書の生データ」の凝集単位で、これは既存の関心の追加にあたる。

## 採らない案

- **`DocumentSurfaceRouter`（`DocumentRendering` の全 13 メソッドを委譲する型）を作らない。** 委譲実装は約 100〜130 行になるが、実質的な判断は「いま PDF か」の 1 箇所だけで、残りは転送コード。型を 1 つ増やして責務が 1 つも増えない間接層になる。
- **`WebViewCommandController` が renderer を `() -> any DocumentRendering` のクロージャで受ける形も採らない。** 現在の注入クロージャはちょうど 3 個（`onZoomChanged` / `onScrollPositionSaved` / `capabilities`）で、`docs/dev/rules/product-code.md` の「親→子へのコールバック注入がクロージャで 3 つを超えたら delegate プロトコルを検討する」に触れる。
- 代わりに `DocumentSurfaces` が `active(for:)` を 1 メソッドだけ公開し、`WebViewCommandController` は computed property を 1 本足す形にする。既存の `renderer.` 呼び出し 12 箇所は無改変で済む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `ViewerWindowController` グループの行数が現状（895 行）から増えていない
- [ ] #2 `ViewerContentView` が `ViewerWebView` への配線を直接持たず、切り出した `DocumentSurfaceStack` が持っている
- [ ] #3 `DocumentRendering` が「振り分ける操作」と「両サーフェスへ配る追随」に分かれており、どちらに属するかが doc コメントで判別できる
- [ ] #4 `applyCodeFont` / `applyCsvNumberFormat` / `applyJumpAvailability` / `noteRename` が「配る」側にあることを、振り分け実装に変えたら落ちるテストで固定している
- [ ] #5 `ViewerStore` グループが 400 行の上限に対して、PDF の Data ケースを受けられるだけの余裕を持っている
- [ ] #6 この整理だけでは PDF の描画は一切変わっていない（`_renderPdf` の iframe 経路は手つかず）
- [ ] #7 `swift test` が通り、swiftlint の main とのベースライン差分がゼロである
<!-- AC:END -->
