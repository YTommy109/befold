---
id: TASK-564.1
title: PDF の描画を WebKit 内蔵プラグインから PDFKit へ移す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-29 00:40'
updated_date: '2026-08-29 12:25'
labels: []
dependencies:
  - TASK-565
  - TASK-564.6
parent_task_id: TASK-564
priority: high
type: task
ordinal: 815000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 目的

PDF を `<iframe>` + blob URL（WebKit 内蔵 PDF プラグイン）で描くのをやめ、`PDFKit` の `PDFView` で描く。TASK-564 配下の 4 機能はすべてこの基盤の上に載るため、これを最初に片付ける。

## 現状（実測 / 2026-08-29 時点）

- 読み込み: `ContentLoader.load(from:fileType:computeHash:)` が Data を **base64 文字列**にし、`ViewerLoadPipeline.load` が `fileType.isBinaryContent` で分岐してこの経路へ流す。上限は `ContentLoader.maxFileSizeBytes`（50MB）。
- 描画: `viewer-src/renderers.ts` の `_renderPdf` が `base64ToBytes`（`viewer-src/encoding.ts`）→ `_createPdfBlobHolder()` の `issue()` で blob URL を作り `<iframe>` の src に入れる。`#diagram-wrap` に `pdf-body` クラス。
- blob の解放: `viewer-src/render.ts` の `render()` 冒頭で `_mmdPdfBlob.release()`。
- CSP: `BefoldKit/Resources/viewer.html` の meta で `frame-src blob:` のみ許可。
- スタイル: `BefoldKit/Resources/style.css` の `.viewer:has(> #diagram-wrap.pdf-body)` ほか。
- `ViewerRenderer` / `ViewerBridge` に PDF 固有の分岐は無い。
- QuickLook 拡張は PDF を扱わない（`FileType.quickLookSupportedExtensions` が `!isBinaryContent` で絞り、`BefoldQuickLook/Info.plist` の `QLSupportedContentTypes` にも `com.adobe.pdf` は無い。`befoldCLITests/QuickLookInfoPlistTests.swift` が担保）。**このタスクの影響範囲外**。

## 論点（実装着手前に `/review-design` で詰める）

- **サーフェス切替の置き場所**: 種別ごとの出し分けは既に「メニュー構築時の分岐」ではなく `ViewerCapabilities` の有効判定に一本化されている（`ViewerCapabilitiesFactory` → `ViewerMenuValidator` / `ViewerToolbarController+State` / `WebViewCommandController`）。PDF サーフェスの分岐も同じ原則で 1 箇所に閉じる必要がある。`ViewerCapabilities` に真偽値を足すのか、描画サーフェスの抽象を 1 つ導入して zoom / print / scroll のコマンドが委譲する形にするのかを決める。ADR 0002 段 2「条件は 1 箇所」を崩さないこと。
- **base64 経路の扱い**: `PDFView` は Data か URL を直接受けられるため、PDF に限れば base64 化（サイズ 1.33 倍）は不要になる。`ContentLoader` のバイナリ経路を PDF と画像で分けるか、共通のまま PDF だけ別に読むかを決める。
- **ファイル監視の再描画**: `FileWatcher → ViewerStore → ViewerRenderer(evaluateJavaScript)` の伝搬が PDF では `PDFView` の差し替えに変わる。再描画時に表示位置を失わないこと（詳細は表示位置の記憶タスク側で扱うが、経路はここで用意する）。
- **印刷**: `capabilities.canPrint` の実体が WKWebView 前提なら PDF 側の印刷経路も要る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PDF が `PDFView` で描画され、`<iframe>` + blob URL 経路を通らない
- [x] #2 `viewer-src/renderers.ts` の `_renderPdf` / `_createPdfBlobHolder` / `_mmdPdfBlob`、`render.ts` の `shape === "pdf"` 分岐、`style.css` の `pdf-body` 規則、viewer.html の CSP `frame-src blob:` のうち PDF のためだけに存在するものが撤去されている
- [x] #3 `viewer-src/zoom.ts` の `_mmdApplyZoom()` にある `pdf-body` 特例が撤去されている
- [x] #4 PDF サーフェスかどうかの分岐が 1 箇所に閉じており、メニュー・ツールバー・コマンドがそれぞれ独自に種別を見ていない
- [x] #5 描画方式の選択（PDFKit を採り pdf.js を採らなかった理由、代償として描画面が 2 枚になること）が `docs/adr/` の ADR として記録されている
- [x] #6 PDF を開く・別種別へ切り替える・PDF へ戻る、を往復してもサーフェスの残留やリークが起きない
- [x] #7 `swift test` が通り、swiftlint の main とのベースライン差分がゼロである
- [x] #8 PDF で ⌘F が「押せるが何も起きない」状態になっていない（canFind が PDF で true のまま dead にならないこと。ADR 0002 が排した形）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
実装着手前の /review-design を実施済み（設計チェックリスト10項目 + responsibility-reviewer + PDFKit API の一次情報裏取りの3本）。
起票時の論点に対する結論と、レビューで新たに出た7件の是正を以下に反映する。

## A. 起票時の論点に対する結論

A1. サーフェス切替の置き場所 → **ViewerCapabilities に真偽値を足さない。**
    PDF かどうかで変わるのは「できるか」ではなく「どう実現するか」であり、
    後者は ADR 0002 段 4 の port（DocumentRendering）の内側の関心。
    既に DocumentRendering port と WebViewDocumentRenderer adapter があり、
    zoom/print/find/jump/scroll/rename は全てここを通る（本番の保持者は
    WebViewCommandController のみ。rg 実測）。PDF は2つ目の adapter として入れる。

A2. base64 経路 → **PDF だけ Data で運ぶ。** PDFView は Data を直接受けられ、
    base64 は 1.33 倍の無駄。画像は data: URI として JS へ渡すため base64 のまま。
    ContentLoader.load は loadData の結果を base64 化する薄い層へ作り替え、
    サイズ上限（50MB）・reject 判定・hash（base64化前の生データ由来）を両経路で共有する。

A3. ファイル監視の再描画 → contentRevision 駆動。updateNSView は revision が
    変わったときだけ PDFDocument(data:) を作り直す。位置の持ち越しは TASK-564.3 だが、
    差し替え前後で currentDestination を持ち越す経路をここで用意する。

A4. 印刷 → capabilities.canPrint = onDocument で PDF でも true。
    **PDF adapter の printDocument を no-op にしない**（能力が true なのに何も
    起きないのは ADR 0002 が排した形）。PDFDocument.printOperation(for:scalingMode:autoRotate:)
    （macOS 10.7+、NSPrintOperation? を返す）を使う。

## B. レビューで出た是正（実装前に確定させたもの）

B1. **DocumentRendering を「操作（振り分ける）」と「追随（配る）」の2群に分ける。**
    applyCodeFont / applyCsvNumberFormat / applyJumpAvailability / noteRename は
    振り分けず**両 adapter へ配る**。
    根拠: (a) WebViewCommandController のコメントが「設定反映を止めると、フォルダーを
    見ている間の設定変更が常駐 WebView に入らないまま取り残される」と名指ししており、
    種別で振り分けると同じ事故が再発する。(b) handleRename は applyURLToWindow を
    noteRename より先に呼ぶため、振り分けると .pdf→.md のリネームで
    ViewerRenderer.handleRename が呼ばれず TASK-401 / TASK-393 が戻る。

B2. **振り分けの真実の源は CurrentDocumentRef ではなく ViewerContentState.fileType。**
    CurrentDocumentRef.url は ViewerStore.pendingURL そのもので、openFile の入口で
    同期的に進む一方、内容の着地は後。URL で振り分けると md→pdf 切替直後に
    「画面は旧 md（WKWebView）なのに命令は空の PDFView へ飛ぶ」区間ができる。
    ViewerCapabilitiesFactory が supportsDiffDisplay で fileURL を使う前例（TASK-338）は
    fail-closed なゲートで性質が違う（早すぎる切替が安全側に倒れる）。
    振り分けは fail-silent なので、描画が確定した面＝ applyDisplayState が
    content と同時に確定させる contentState.fileType を見る。

B3. **DocumentSurfaceRouter（13メソッドの委譲型）を作らない。**
    DocumentRendering は1プロパティ+12メソッドで、委譲実装は約100〜130行のうち
    判断は1箇所だけ。責務が増えないただの間接層になる。
    代わりに DocumentSurfaces（新設）が web/pdf の proxy と adapter を持ち
    active(for:) を1メソッドだけ公開し、WebViewCommandController は
    `private var renderer: any DocumentRendering { surfaces.active(...) }` の
    computed property を1本足す。既存の renderer. 呼び出し12箇所は無改変。
    注入クロージャを増やす案（() -> any DocumentRendering）も採らない
    （現在ちょうど3個で、docs/dev/rules/product-code.md の
    「3つを超えたら delegate を検討」に触れる）。

B4. **PDF の Data は ViewerContentState.DisplayState に載せる（data: Data?）。**
    PDFPreviewView が filePath からディスクを読み直す形にしない
    （開始時の無効化も着地時の一致確認も無い経路になる）。
    DisplayState は「フィールドを増やすと片方の分岐だけ更新し忘れる事故を構造的に防ぐ」
    ために作られた組なので、ここへ足すのが単一情報源の規約に沿う。
    受け取りは ViewerStore ではなく ViewerContentState に置く
    （ViewerStore グループは実測394行で上限400まで残り6行）。
    contentHash の「読み込み成功時だけ non-nil」の不変条件を .binary にも持たせる。

B5. **破損 PDF（PDFDocument(data:) が nil）は既存の表示に乗らない新状態。**
    読み込みは成功しているので rejectReason は nil、UnsupportedFileView は出ず
    黙って空白になる。読み込み経路で PDFDocument の生成まで行って失敗を
    RejectReason へ落とす（新ケース）。放置しない。

B6. **PDFPreviewView に isVisible 抑止を入れる。** ViewerRenderer+ContentUpdate が
    guard isVisible で再描画を止めているのと同じ理屈（ADR 0002 段 5）。
    無いと、フォルダー一覧を見ている間も PDF が書き換わるたび PDFDocument の
    再パースが走る。filePreview(isVisible:) の値をそのまま渡す。

B7. **canFind が PDF で true のまま dead になる問題を塞ぐ。**
    canFind = onDocument && !isDirectHTMLMode なので PDF でも true。
    PDF adapter の openFind を no-op にすると「メニューは押せるが何も起きない」= B/A4 と
    同じ ADR 0002 違反になる。canFind に !isBinaryContent を加える
    （画像でも同様に dead だった既存の穴も同時に塞がる）。
    PDFView によるPDF内検索の実装は別タスクへ切り出す。

## C. 実装順序

1. ViewerContentView から DocumentSurfaceStack を切り出す（PDF を足す前に切る。
   後回しにすると22引数の配線の隣に2枚目のサーフェス配線が並んだ状態が既成事実になる）
2. DocumentSurfaces / PDFViewProxy を新設し、ViewerWindowController の
   stored property を webViewProxy から surfaces 1本へ寄せる
   （ViewerWindowController グループは実測895行、例外枠900まで残り5行しかない）
3. DocumentRendering を B1 の2群へ作り替える
4. ContentLoader.loadData / ViewerLoadPipeline の .binary / DisplayState.data（B4）
5. PDFPreviewView と PDFDocumentRenderer を新設（B5/B6 込み）
6. canFind の是正（B7）
7. JS 側の PDF 専用コード撤去（_renderPdf / _createPdfBlobHolder / _mmdPdfBlob /
   shape==='pdf' 分岐 / zoom.ts の pdf-body 特例 / encoding.ts の base64ToBytes /
   style.css の pdf-body 3規則 / viewer.html の CSP frame-src blob:）
8. 契約テストを Swift 側にも張る（B/項目7）:
   (a) バンドルに shape === "pdf" が無いこと（ViewerBridgeContractTests を反転）
   (b) FileType.pdf → PDF adapter が返ること
   (c) ViewerLoadPipeline.load(.pdf) が .binary を返すこと（.full へ落ちない）
   PDFViewProxy には既定引数を付けない（渡し忘れが静かに別インスタンスへ落ちる
   TASK-319 型の事故を構造で塞ぐ）
9. ADR 0009 を書く（PDFKit を採り pdf.js を採らなかった理由、描画面が2枚になる代償と
   それを port の内側へ閉じたこと）
10. swift test / swiftlint ベースライン差分ゼロ / npm run lint / jest

## D. 未確認（実装前に実機・ヘッダーで確認する）

- PDFView が標準処理するキー（矢印 / PageUp/Down / Space / Home/End）。
  Apple のドキュメントに明記が無い。Space / Shift+Space / j / k / Shift+↓↑ の6件は
  現在 viewer-src/keyboard.ts の resolveScrollKey にあり、Help の一覧
  （ViewerShortcutCatalog.scrollItems、jest と件数を相互固定）に載っている。
  PDF で失われる分の扱いは別タスクへ切り出す。
- autoScales = true のときに scaleFactor へ代入した場合の挙動（明記なし）
- document 再代入時のスクロール位置・倍率の保持/リセット（明記なし）
- 別 PDFDocument のページを指す PDFDestination に go(to:) した場合（明記なし）
- PDFDocument / PDFDestination は Sendable 非準拠（PDFView は Sendable 準拠）。
  Data はバックグラウンドで運び、PDFDocument の生成は MainActor 上（updateNSView）で行う。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装着手前の設計レビュー（2026-08-29）

`/review-design` を 3 本回した（設計チェックリスト 10 項目 / responsibility-reviewer / PDFKit API の一次情報裏取り）。結果は Implementation Plan の A・B・C・D に反映済み。

**先行タスクを分離した**: 構造整理（`DocumentSurfaces` の新設・`ViewerContentView` からの `DocumentSurfaceStack` 切り出し・`DocumentRendering` の 2 群分割・`ViewerStore` の余裕づくり）は TASK-564.6 へ出し、依存を張った。実測で `ViewerWindowController` が 895/900 行、`ViewerStore` が 394/400 行と、どちらも PDF 追加分を受けられないため。

**このタスクに含めることにしたもの**: `canFind` の是正（AC #8）。`canFind = onDocument && !isDirectHTMLMode` のため PDF でも true になり、PDF adapter の `openFind` を no-op にすると「メニューは押せるが何も起きない」形になる。`!isBinaryContent` を加えて塞ぐ（画像で既に dead だった同じ穴も同時に閉じる）。

## 繰り越した論点（このタスクでは扱わないが、失わないよう記録する）

1. **PDF 内検索の実装**（`PDFView` / `PDFDocument.findString`）。上の `canFind` 是正は「押せるのに効かない」を塞ぐだけで、PDF で検索できるようにはしない。必要になった時点で起票する。
2. **キーボードスクロール 6 件が PDF で失われる**。Space / Shift+Space / ↓j / ↑k / Shift+↓ / Shift+↑ は `viewer-src/keyboard.ts` の `resolveScrollKey` にしかなく、Swift 側に入口が無い。Help の一覧（`ViewerShortcutCatalog.scrollItems`）は種別非依存で 6 件を掲載し、`ViewerShortcutCatalogTests` と jest 側が件数を相互固定しているため、PDF では説明と実態が食い違う。`PDFView` が標準でどのキーを処理するかは Apple のドキュメントに明記が無く、実機確認が要る。
3. **破損 PDF（`PDFDocument(data:)` が nil）の表示**。読み込み自体は成功しているため `rejectReason` は nil のままで `UnsupportedFileView` が出ず、黙って空白になる。Implementation Plan の B5 に、読み込み経路で検出して `RejectReason` の新ケースへ落とす方針を書いてある。このタスクに含めるかは着手時に判断する。

## 実装（2026-08-29）

Implementation Plan の C を上から実施した（1 は TASK-564.6 で完了済み）。

### 読み込み（A2 / B4 / B5）

- `ContentLoader.loadData(from:computeHash:)` を新設し、`load` は「その結果を base64 へ写すだけ」の薄い層にした。サイズ上限（50MB）・reject 判定・hash の作り方は両経路が共有する（`PDFSurfaceLoadTests.bothBinaryPathsShareLimitsAndHash` が固定）。
- `ViewerLoadPipeline.Outcome` に `.binary(ContentLoader.LoadedData)` を足し、`fileType == .pdf` だけがそこへ流れる。画像は `.full`（base64）のまま。
- 破損 PDF は `RejectReason.damagedDocument`（新ケース）へ落とす。判定は `PDFDataProbe.isReadable` に置き、表示側が `PDFDocument` を作る条件と同じ事実を見る。B5 の「含めるかは着手時に判断」は**含める**を選んだ。含めないと読み込み成功のまま空白になり、バナーも出ない。
- `ViewerContentState.DisplayState` に `data: Data?` を足した（B4 のとおり `ViewerStore` ではなく `ViewerContentState` 側の写しで受ける）。

### 描画（B3 / B6）

- `PDFViewProxy` / `PDFDocumentRenderer` / `PDFPreviewView` を新設。`DocumentSurfaces` は proxy と adapter を 2 組持ち、`operating(on:)` の 1 行（`fileType == .pdf`）だけが宛先を分ける。`syncingAll` は 2 要素。
- `PDFPreviewView` は `contentRevision` 駆動で、`isVisible` が false の間は差し替えない（B6）。PDF 以外を表示中は `data: nil` を渡して文書を外す（面が古い文書を抱えたまま印刷されるのを防ぐ）。
- ズームは `scaleFactorForSizeToFit` を基準に掛け直す。そうしないと同じ 1.0 が面ごとに違う意味になる。印刷は `PDFDocument.printOperation(for:scalingMode:autoRotate:)`（A4 のとおり no-op にしない）。

### 能力（B7 / AC #8）

`canFind` に加えて **`canJump` にも** `!isBinaryContent` を足した。理由は同じ（PDF 面にジャンプの実体が無く、開けても no-op になる）。画像で既に dead だった穴も同時に閉じる。

### JS 側の撤去（AC #2 / #3）

`_renderPdf` / `_createPdfBlobHolder` / `_mmdPdfBlob` / `render.ts` の `shape === 'pdf'` 分岐 / `renderShape` の pdf 特例 / `zoom.ts` の `pdf-body` 特例 / `encoding.ts` の `base64ToBytes` / `style.css` の `pdf-body` 3 規則 / viewer.html の CSP `frame-src blob:` を撤去。`ViewerBridgeContractTests` に「バンドルに `shape === "pdf"` と `pdf-body` が無いこと」の走査を足し、復活したら落ちるようにした。

### 検証

- `swift test` 1748 件すべて成功。
- swiftlint の main とのベースライン差分ゼロ（`git archive origin/main` を別ディレクトリへ展開して測定。双方 54 件、ルール×ファイルの新規・解消ともに空）。
- `npm run lint` / `typecheck:viewer` / `format:check` / `check:viewer-cycles` / jest 621 件すべて成功。`viewer-bundle.js` は再ビルド済み。
- markdownlint / check-doc-symbols / check-doc-citations すべて通過。

### 既存テストの変更

`ViewerStoreBinaryContentTests` の PDF ケースは `"%PDF-1.4"` という文字列を使っていたが、これは `PDFDocument` が開けないため新しい経路では拒否される（= 正しい振る舞い）。1 ページの実 PDF を作る `minimalPDFData()` へ差し替え、base64 経路（画像）と生データ経路（PDF）のテストを分けた。破損 PDF の拒否は `damagedPDFMarksUnsupported` で別途固定。

### 未確認（AC #6）

「PDF → 別種別 → PDF の往復でサーフェスの残留やリークが起きない」は**目視確認できていない**。実装上は面を破棄せず重ね順で出し分け、PDF 以外の間は `data: nil` で文書を外す形にしてあるが、このセッションでは画面のキャプチャが取れなかった（`screencapture` が "could not create image from display" で失敗する環境）。アプリの起動・PDF／破損 PDF／md の切替でクラッシュしないことまでは実機で確認済み。**AC #6 はユーザーの目視で確認が必要**。

## 繰り越し（Implementation Notes の「繰り越した論点」を更新）

1. PDF 内検索の実装 — 未着手のまま。`canFind` は閉じたので「押せるのに効かない」状態ではなくなった。
2. キーボードスクロール 6 件が PDF で失われる — 未着手。ADR 0009 の Consequences にも記録した。
3. 破損 PDF の表示 — **このタスクで対応した**（`damagedDocument`）。

## AC #6 の検証を追加（2026-08-29 / 目視の代わり）

`screencapture` が使えない環境だったため未検証のまま残していた「PDF → 別種別 →
PDF の往復でサーフェスの残留やリークが起きない」を、**オフスクリーン描画の実測**で
固定した（`PDFSurfaceRenderingTests`）。`NSView.cacheDisplay(in:to:)` は画面収録の
権限も窓も要らずにビューを描かせられる（`SettingsViewSnapshotTests` と同じ手）。

`別種別へ移ると面から文書が外れ、戻すと再び描かれる` が、
描画→ `document = nil`（`PDFPreviewView` が `data: nil` で通る経路）→ 描画→復帰、
の各段で画素を測る。ページが出ている間は明るい画素が 30% 超、外した後は 1% 未満、
戻すと再び 30% 超。これで「隠しているだけで文書を抱えたまま」の状態が入り込んだら落ちる。

測り方の注意（実測）: `backgroundColor` を白に塗ると `cacheDisplay` にページが
写らなくなる（PDFKit が別の描画経路へ行く）。既定の地（暗い
`underPageBackgroundColor`）のまま、**明るい画素**でページの有無を測ること。
<!-- SECTION:NOTES:END -->
