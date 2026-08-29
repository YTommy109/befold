---
id: TASK-564.6
title: 描画サーフェスの受け皿を作り、PDF を足せる形にする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-29 10:16'
updated_date: '2026-08-29 11:10'
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
- [x] #1 `ViewerWindowController` グループの行数が現状（895 行）から増えていない
- [x] #2 `ViewerContentView` が `ViewerWebView` への配線を直接持たず、切り出した `DocumentSurfaceStack` が持っている
- [x] #3 `DocumentRendering` が「振り分ける操作」と「両サーフェスへ配る追随」に分かれており、どちらに属するかが doc コメントで判別できる
- [x] #4 `applyCodeFont` / `applyCsvNumberFormat` / `applyJumpAvailability` / `noteRename` が「配る」側にあることを、振り分け実装に変えたら落ちるテストで固定している
- [x] #5 `ViewerStore` グループが 400 行の上限に対して、PDF の Data ケースを受けられるだけの余裕を持っている
- [x] #6 この整理だけでは PDF の描画は一切変わっていない（`_renderPdf` の iframe 経路は手つかず）
- [x] #7 `swift test` が通り、swiftlint の main とのベースライン差分がゼロである
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 検証結果（実測）

- `swift test --skip Integration --skip FileWatcherTests`: **1629 件すべて成功**（着手前は 1621 件。増分 8 件は DocumentSurfaceDispatchTests 7 件と ViewerContentViewStoreIsolationTests の追加 1 件）
- swiftlint の main とのベースライン差分: **ゼロ**（`git archive origin/main` を別ディレクトリへ展開して測定。双方 54 件で一致）
- 型グループ行数: `ViewerWindowController` 895（着手前と同値、例外枠 900）、`ViewerStore` 394 → **370**、`ViewerContentView` 111 → **77**、新設 `DocumentSurfaceStack` 91 / `DocumentSurfaces` 63 / `DocumentRendering` 106 / `ViewerContentState` 155 → 201
- JS 側の差分: `git diff origin/main -- BefoldApp/viewer-src BefoldApp/BefoldKit/Resources` が**空**。PDF の iframe 経路は手つかず（AC #6）

## AC #4 は、テストより上位の担保になった

「配るべきものを振り分けてしまう」実装は**コンパイルが通らない**。
`WebViewCommandController.renderer` の型が `any DocumentSurfaceOperating` で、
`applyCodeFont` などの追随メソッドを持たないため。実際に `applyCodeFont` を
`renderer.applyCodeFont(...)` へ書き換えて確認した（実測）:

```
error: value of type 'any DocumentSurfaceOperating' has no member 'applyCodeFont'
```

`.claude/CLAUDE.md`「決めたことには、破れたら落ちるものを付ける」の 2 つの選択肢のうち、
テストではなく**破りようのない構造**のほうが得られた。`DocumentSurfaceDispatchTests` は
その上で、宛先の書き方（`surfaces.syncingAll` を回っているか）をソース走査で固定する。
面が 1 枚のうちは呼び出し回数では差が出ない（配っても振り分けても同じ 1 枚に届く）ため、
回数のテストだけでは担保にならない。

## 途中で直した無関係の不具合

`SettingsViewSnapshotTests` の「負の数の選択肢の見本が右端で揃っている」が HEAD 時点で
既に失敗していた（本タスクの変更とは無関係。ファイルを退避して切り分け済み）。
判定が「地はほぼ白、文字は暗い」を前提にしているため、macOS の外観がダークだと
全行が文字と判定されて行のかたまりが 1 つに潰れる（rows.count が 4 ではなく 1）。
撮る側の `window.appearance` を `.aqua` に固定して別コミットで修正した。

## TASK-564.1 への申し送り

- PDF の面を足す変更点は `DocumentSurfaces.operating(on:)` の中身と `syncingAll` の要素、
  および `DocumentSurfaceStack` への 1 枚追加に閉じる。`WebViewCommandController` は
  種別を見ないので触らない
- 宛先の判定は `CurrentDocumentRef.renderedFileType`（= `ViewerContentState.fileType`）。
  `url` 側（`ViewerStore.pendingURL`）を使わないこと。理由は
  `DocumentSurfaces.operating(on:)` の doc コメントに書いてある
- `ViewerLoadPipeline.Outcome` に Data ケースを足したときの受け手は
  `ViewerContentState.DisplayState.init(outcome:fileType:)`（extension 側。struct 本体に
  書くとメンバワイズ init が消える）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TASK-564.1（PDF を PDFKit の PDFView で描く）に着手できる形へ、既存の構造を先に整えた。PDF そのものは足していない（`git diff origin/main -- BefoldApp/viewer-src BefoldApp/BefoldKit/Resources` が空）。

変更は 3 段。

1. **描画面への配線を `DocumentSurfaceStack` へ切り出す。** `ViewerContentView` はフォルダー一覧との出し分けだけを持つ（111 → 77 行）。PDF を足してから切ると、22 引数の配線の隣に 2 枚目のサーフェス配線が並んだ状態が既成事実になるため、先に切った。
2. **`DocumentRendering` を宛先で 2 群へ分け、束を `DocumentSurfaces` へ寄せる。** `DocumentSurfaceOperating`（いま描いている 1 枚へ振り分ける）と `DocumentSurfaceSyncing`（すべての面へ配る）。設定反映とリネーム追随を後者に置いたのは、振り分けると既存コメントが名指ししている 2 つの事故が戻るため（設定の取り残しが種別の形で再発する / `handleRename` が `applyURLToWindow` を先に呼ぶので対応形式が変わるリネームで旧側の面が追随しない = TASK-401 / TASK-393）。宛先は `ViewerContentState.fileType` で決める（`pendingURL` は内容の着地より先に進むため、URL で決めると切替直後に命令が無言で捨てられる）。`ViewerWindowController` の stored property は `webViewProxy` から `surfaces` 1 本になり、行数は 895 のまま（例外枠 900 を面の枚数で食い潰さない）。
3. **読み込み結果 → 表示状態の写しを `ViewerContentState` へ移す。** `Outcome` に case が増えるたび `ViewerStore` グループが太る形をやめた（394 → 370 行）。TASK-564.1 の Data ケースの受け手はここに入る。

検証: `swift test` 1629 件すべて成功、swiftlint の main とのベースライン差分ゼロ（origin/main を別ディレクトリへ展開して測定、双方 54 件）。

AC #4 は当初テストで固定する想定だったが、**型でそもそも書けない**形になった。`WebViewCommandController.renderer` は `any DocumentSurfaceOperating` で追随メソッドを持たないため、配るべきものを振り分ける実装はコンパイルが通らない（実際に書き換えて確認: `error: value of type 'any DocumentSurfaceOperating' has no member 'applyCodeFont'`）。`DocumentSurfaceDispatchTests` はその上で宛先の書き方をソース走査で固定する（面が 1 枚のうちは呼び出し回数では差が出ないため）。

`docs/dev/native-app-design.md` のコンポーネント表に `DocumentSurfaceStack` / `DocumentSurfaces` を追加し、`DocumentRendering` の記述を 2 群構成へ更新した。

別件として、HEAD 時点で既に失敗していた `SettingsViewSnapshotTests`（ダークモードで地と文字の判定が反転する）を別コミットで修正した。
<!-- SECTION:FINAL_SUMMARY:END -->
