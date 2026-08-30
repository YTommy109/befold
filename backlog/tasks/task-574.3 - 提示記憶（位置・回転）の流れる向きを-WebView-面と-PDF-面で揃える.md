---
id: TASK-574.3
title: 提示記憶（位置・回転）の流れる向きを WebView 面と PDF 面で揃える
status: Done
assignee: []
created_date: '2026-08-30 03:38'
updated_date: '2026-08-30 05:23'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-574
priority: medium
type: task
ordinal: 834000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
同じ「窓の提示記憶」（`WindowPresentationMemory`）に対して、面ごとにデータフローの向きが違う。

| 値 | WebView 面 | PDF 面 |
| --- | --- | --- |
| スクロール位置 | JS の `scrollPositionChanged` → `recordScrollPosition` で**常時 push** | `saveScrollPositionBeforeTransition` からの**切替時 pull のみ**（呼び出し元は `performFileSwitch` と `setDisplayMode` の 2 箇所） |
| 回転 | （無し） | 提示開始時に `store.pdfRotation` へ読み込むが以後 store へ戻さず、退出時に `currentRotation` で面から pull |

結果として `WindowPresentationMemory` に PDF 専用の `rotations` 表が生え、`WebViewCommandController.rotate / currentRotation` は名前が web 面のまま両面へ dispatch している。今は動くが、次に PDF 固有の記憶（TASK-570 の検索語など）を足すたびに同じ二重構造が増える。

## 到達したい形

- 位置・回転とも、両面で同じ向き（push に揃えるなら PDF 面の `boundsDidChange` から `recordScrollPosition` へ、pull に揃えるなら web 面も切替時だけ）。どちらに揃えるかは着手時に `/review-design` で決める。判断の材料: web 面の push は「保存が遅れて届く」経路（`ViewerDocumentPresenter` の late-arriving save catch-up）を必要としており、pull に揃えるとその経路ごと消せる可能性がある
- `WindowPresentationMemory` の表が面固有でなく「提示記憶の種類」で並ぶ
- `WebViewCommandController` の回転 API の名前が実態（両面へ dispatch）に合う

TASK-570（PDF 内検索）が同じ記憶機構へ値を足す見込みなので、そちらより先に済ませる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 スクロール位置と回転が、WebView 面と PDF 面で同じ向き（push か pull か）で `WindowPresentationMemory` へ届く
- [x] #2 `WindowPresentationMemory` に面固有の分岐（PDF だけの表・web だけの表）が無い
- [x] #3 回転を扱う API の名前に web 面を指す語が残っていない
- [x] #4 揃えた向きを破ると落ちるテストがある（例: PDF 面で位置を変えたのに記憶が更新されない、または web 面が切替以外で記憶を書いている）
- [x] #5 `/review-design` の結果が Implementation Plan に反映されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 着手前調査（2026-08-30）

### 起票時の仮説は実測で否定された

Description は「pull に揃えると late-arriving save catch-up の経路ごと消せる可能性がある」と書いていたが、**消せない**。catch-up が待っているのは push（JS の `scrollPositionChanged` 通知）ではなく `webView.evaluateJavaScript(ViewerBridge.currentScrollPositionScript)` の**ラウンドトリップ**（`WebViewDocumentRenderer.currentScrollPosition`）。web 面の位置取得は JS 経由でしか成立しないので、pull に揃えても非同期性は残り catch-up は要る。

### 判明した実態: web 面は push と pull の**両方**を持っている

`saveScrollPositionBeforeTransition` は種別を見ずに `webViewCommands.saveCurrentScrollPosition` を呼び、`DocumentSurfaces.operating(on:)` が面を選ぶ。つまり **pull は既に両面が通っている**。非対称なのは web 面だけが**追加で** push を持っていること。

- push の経路: JS `scrollPositionChanged` → `BridgeMessageRouter.handleScrollPositionChanged` → `ViewerRendererDelegate.renderer(_:didChangeScrollPosition:for:mode:)` → `ViewerWindowController+Renderer` → `ViewerDocumentPresenter.recordScrollPosition` → `WindowPresentationMemory.setScrollPosition`
- **この経路の消費先は `setScrollPosition` ただ 1 つ**（grep 実測: `didChangeScrollPosition` / `scrollPositionChanged` の本番参照を全数確認。他の用途は無い）

### pull だけで足りるか（実測）

記憶を読むのは `beginPresentingDocument` の 2 呼び出し元だけ（`ViewerWindowPresentationEntryPointTests` がソース走査で件数を固定）。

- `ViewerWindowController.init` — **新規ウィンドウの生成時**。前のファイルが無いので保存すべきものが無い
- `ViewerWindowController+FileNavigation.performFileSwitch` — `saveScrollPositionBeforeTransition` を**必ず先に呼ぶ**

`ViewerWindowManager.openViewer` は「同じファイルの既存窓を前面化する」か「新規窓を作る」かの二択で、**別ファイルを既存窓へ流し込む経路は無い**（別ファイルはサイドバー → `performFileSwitch`）。ライブリロード（FileWatcher）は `beginPresentingDocument` を通らないので記憶を読み直さない。

→ **記憶の観点では web の push は冗長**。撤去しても記憶が古くなる経路は見つからなかった。

### 撤去すると一緒に消えるもの

`ViewerWindowScrollPositionNotificationTests`（2 テスト）は「切替後に届いた切替前ファイルの通知を切替先のキーへ記録しない」「url が nil の通知を記録しない」を守っている。**どちらも push が非同期に届くこと自体が生む危険**なので、push を撤去すれば守るべき対象ごと消える。

### 方針の分岐（ユーザー判断待ち）

- **案 pull（推奨）**: web の push を撤去し、両面とも「切替直前に 1 回 pull」に揃える。経路が 1 本減り、テストも 2 本減る。ただし **WebView 面の挙動を変える変更**であり、タスクの表題（PDF 面を揃える）より広い
- **案 push**: PDF 面に `NSClipView` の `boundsDidChangeNotification` 購読を足して push 側へ揃える。PDF 面の変更で閉じるが、**機構が増える**（TASK-574 が撤去したばかりの方向）

回転（AC #2 / #3）はどちらの案でも別途対応が要る。

## 方針決定（ユーザー判断 / 2026-08-30）

**案 pull を採用。** web 面の push 経路を撤去し、両面とも「切替直前に 1 回 pull」へ揃える。

## 訂正: 「web の push は冗長」は誤り（2026-08-30）

上の調査で「記憶の観点では web の push は冗長」と書いたが、**誤り**。pull を同期だと扱っていた。

`performFileSwitch`（`ViewerWindowController+FileNavigation.swift`）は同一同期区間で `saveScrollPositionBeforeTransition()` → …→ `beginPresentingDocument(at: newURL)` と進み、**pull の完了を待たずに記憶を読む**。pull が同期で完了するのは PDF 面だけ（`PDFDocumentRenderer.currentScrollPosition` は即 completion）で、web 面は `evaluateJavaScript` のラウンドトリップ。

したがって切替時点で web の記憶に正しい値が入っているのは、**push が 200ms デバウンスで書き続けているから**。push は冗長ではない。

### git 履歴の裏付け

- 導入は `36cdc7c5`「feat: スクロール位置を UserDefaults に永続化する (#172)」（2026-07-11）。**push と pull は同じコミットで同時に入っており**、push が先で pull が後、ではない。役割分担は最初から **push = 継続保存 / pull = 切替直前 200ms の取りこぼしの確定**。
- `saveScrollPositionBeforeTransition` という名前が付いたのは `488e40a7` で、2 箇所に複写されていた同一 idiom の集約にすぎない（振る舞いの追加ではない）。
- TASK-394 がこの非同期性を起票済み。「保存完了を待ってから切替」「`performFileSwitch` の非同期化」はどちらも**採らないと明記**。採った `applySavedScrollPositionToLiveValue` には既知の限界があり、保存完了が切替先の `applyRender` より後に届くと**復元値は直るが画面への再注入は行わない**。
- `ViewerWindowPresentationEntryPointTests.saveScrollPositionBeforeTransitionHasExactlyTwoCallSites` が pull の契機を 2 つに固定しているため、pull を増やして push を代替する道もテストで塞がれている。

→ **pull へ揃えると TASK-394 の症状が A→B→A の往復で常時化する。**

### ライブリロードは無関係（確認済み）

ライブリロードの位置保持は `WindowPresentationMemory` を使わない。`ContentUpdatePlanner` の `restoreFromPersistedPosition` は `RenderedStateMirror.isFileOrModeSwitch` が false のとき注入せず、JS 側（`viewer-src/render.ts`）が render 直前の `scrollTop` を `fallbackScrollTop` として自前で退避・再設定する。push 撤去はここを壊さない（壊れるのは切替の復元）。

### 非対称の真因

**面ごとの流儀の違いではなく、位置取得が同期か非同期かというプラットフォームの違い。** PDF 面は同期に取れるので pull だけで足り、web 面は非同期なので push が要る。「向きを揃える」は、この差を消せる場合にしか成立しない。

## 再訂正: 「常時化する」も過剰（2026-08-30）

上の訂正で「pull へ揃えると TASK-394 の症状が A→B→A で常時化する」と書いたが、**これも測らずに書いた過剰な表現**だった。

### 決め手: 既存テストが既に「push の無い世界」を測っている

`ViewerWindowScrollRestoreRaceTests` の `ViewerWindowControllerFixture` は `documentRenderer:` に `DeferredScrollRenderer` を注入するだけで、**push 経路（実 WKWebView からの `ViewerRendererDelegate` 通知）を駆動していない**。つまりこのテストは push 非依存の状態を再現しており、そこで「A→B→A 直後は復元値 0 → `flushPendingSaves()` で記憶 640・復元値 640」が緑で通っている。**push が無くても後追い補正が値を回復させる。**

### 構造上の理由

`saveScrollPositionBeforeTransition` は**すべての切替契機で呼ばれ、その completion が無条件に `recordScrollPosition` する**。「その文書を離れれば必ず位置が記憶される」は push の有無によらず成立する。push が変えるのは到着の早さだけ。

| | push あり | push なし |
| --- | --- | --- |
| 通常の切替 | 記憶は最新 | 離脱時の pull が書く（同じ） |
| 1 ラウンドトリップ以内の往復 | 即座に正しい | 後追い補正が値を直す |
| 残余 | — | TASK-394 の**既知の限界**（値は直るが再注入しない） |

残余は TASK-394 が「発生窓は狭い」「priority: low」として**受け入れ済み**の限界であり、新規の退行ではない。

### 時系列の確認（ユーザー指摘）

TASK-394 は 2026-08-09。PDFKit 化（TASK-564）と永続化廃止（TASK-565）は 2026-08-29 で **20 日後**。394 の記述は 2 つの大きな変更より前のもので、現在の仕様として読んではいけなかった。

なお push の当初の目的は `36cdc7c5`「スクロール位置を **UserDefaults に永続化**する」の「アプリ終了時やウィンドウ破棄時にも最新の位置が保存されるよう継続的に送る」（`viewer-src/scroll.ts` に今も残るコメント）。**TASK-565 で永続化をやめ窓の生存期間だけの記憶にした時点で、この目的は失われている。**

→ **当初方針どおり pull へ揃える。**

## 実装（2026-08-30）

### 撤去したもの（push 経路）

- JS: `viewer-src/scroll.ts` の `_mmdPostScrollPosition` / `_mmdInitScrollNotify` / デバウンスのタイマ、`viewer-src/bridge.ts` の `_MSG_SCROLL_POSITION_CHANGED`、`init.ts` の配線
- Swift: `ViewerBridgeMessage.scrollPositionChanged` と `PayloadKey.ScrollPositionChanged`、`ViewerBridge.scrollPositionChangedMessageName`、`BridgeMessageRouter.handleScrollPositionChanged`、`ViewerRendererDelegate.renderer(_:didChangeScrollPosition:for:mode:)` とその既定実装、`ViewerWindowController+Renderer` の実装
- テスト: `ViewerWindowScrollPositionNotificationTests`（push の非同期性そのものを守っていた 2 テスト）、`ViewerRendererMessageHandlingTests` の scroll 系 4 テスト、jest の「スクロール通知のデバウンス」3 テスト

### 併せて簡単になったもの

`_createScrollSync` から `beginRender` と `docPathTracker` の依存が消えた。文書パスの採用をスクロール側に置いていたのは「デバウンス通知の破棄とパスの採用が同時でなければ、旧文書の位置が新パスのキーで通知される」ためで、**通知が無くなった時点でこの結び付き自体が消えた**。採用は `render.ts` が `_mmdDocPath.adoptPending()` を直接呼ぶ形にした。

### テストの移設（担保を落とさない）

文書パスの採用規則（予告は render まで採用しない / 予告なしの再描画で保つ / rename の 3 ケース）は scroll の通知を観測点にしていた。**規則そのものは倍率の通知が同じ `_mmdDocPath` を使うので残る**ため、観測点を `zoomChanged` へ移して 4 件を維持した（2 件は zoom 側に既存の重複があったので移さず）。

### AC #2 / #3

- `WindowPresentationMemory` の doc から面固有の言い回しを除き、「表は記憶の種類で並べ、どの面が使うかは能力が決める」と明記
- `WebViewCommandController` → **`DocumentCommandController`** に改名（53 参照 / 18 ファイル、テスト 2 ファイルもリネーム）。この型は `DocumentSurfaces` 経由で両面へ dispatch しており、`rotate(byDegrees:)` / `currentRotation` を含めて web 面を指す語が名前に残っていた。`docs/adr/0002` / `0009` / `native-app-design.md` も追随（`superpowers/plans/` はスナップショット層なので触らない）

### AC #4（向きを破ると落ちるもの）

`PresentationMemoryWriteDirectionTests` を新設。(a) 撤去した push の名前 5 つがソースへ復活していないこと、(b) `presentationMemory.setScrollPosition` の呼び出しが 1 箇所だけであること、をソース走査で固定する。

**トリップワイヤ確認済み**: `scroll.ts` に `_mmdInitScrollNotify` の文字列を 1 行足すと実際に落ちる（`offenders → ["scroll.ts: _mmdInitScrollNotify"]`）ことを確認し、その後戻した。空振りしていない。

### 検証

- `swift test` **1805 tests / 293 suites 緑**
- `npm test` **615 tests / 13 suites 緑**
- `npm run typecheck:viewer` / `lint` / `format:check` / `check:viewer-cycles` すべて 0 件
- `viewer-bundle.js` を再生成済み（`check:viewer-bundle` の diff が出ない状態）
- swiftlint ベースライン: main 54 → head 53。**真の新規 0**、解消 1（削除したテストファイルの `type_name`）
- markdownlint / `check-doc-symbols.sh` / `check-doc-citations.sh` すべて 0 件
- `xcodegen generate` 実行済み（ファイルの追加・リネームがあるため）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
スクロール位置が提示記憶へ届く向きを、両面とも「切替直前の pull」1 本へ揃えた。web 面だけが持っていた push（スクロールのたびに JS から送る継続通知）を撤去した。

撤去の根拠は、その目的が既に失われていたこと。push は 36cdc7c5「スクロール位置を UserDefaults に永続化する」で「アプリ終了時やウィンドウ破棄時にも最新の位置が保存されるよう」入れられたが、TASK-565 で永続化をやめ窓の生存期間だけの記憶にした時点で、その目的は消えていた。位置が記憶に入るのは今も昔も「その文書を離れるとき」で、そこは pull が担っている。

副次的に、文書パスの採用がスクロール側から切り離せた（デバウンス通知の破棄と同時でなければならない、という結び付きが通知ごと消えたため）。採用規則の担保は倍率の通知へ観測点を移して維持した。

あわせて `WebViewCommandController` を `DocumentCommandController` へ改名した（両面へ dispatch する型なのに回転 API の名前が web 面を指していた）。`WindowPresentationMemory` の doc からも面固有の言い回しを除いた。

向きが戻らないことは `PresentationMemoryWriteDirectionTests` がソース走査で固定する（トリップワイヤが実際に落ちることを確認済み）。検証: swift 1805 / jest 615 全緑、swiftlint 新規違反 0、JS の型・lint・整形・循環すべて 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
