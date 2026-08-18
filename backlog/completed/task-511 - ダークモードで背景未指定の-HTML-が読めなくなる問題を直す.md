---
id: TASK-511
title: ダークモードで背景未指定の HTML が読めなくなる問題を直す
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-17 10:35'
updated_date: '2026-08-17 11:13'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 740000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状

ダークモードで `.html` / `.htm` を開くと、文字がほぼ読めない。実例: `sample/sample.html` は `body { color: #24292f }` を指定するが `background` を指定していないため、`#24292f` の文字が befold のダークキャンバス `#1E1E1E` の上に載る。

## 原因

befold は HTML 描画で前景色（文字色）を文書に委ね、背景色（キャンバス）は befold 側が保持している。所有権が割れているのが原因。

- `BefoldApp/BefoldRenderKit/ViewerWebViewFactory.swift:87` が `drawsBackground = false` を強制し、WebKit の既定のキャンバス描画を殺している
- キャンバス色は `BefoldApp/befold/Viewer/ViewerTheme.swift:11-16`（dark = `#1E1E1E`）
- iframe/srcdoc 経路（`BefoldApp/viewer-src/renderers.ts:111-135`、QuickLook 等）にも背景指定がない

Markdown / コード / CSV / Mermaid は befold が前景色も背景色も持つため問題にならない。HTML だけが例外。

## ブラウザの挙動（あるべき姿）

キャンバス色は UA スタイルシートではなく `color-scheme` が決める。

| ページの宣言 | OS ダーク時にブラウザが塗る背景 |
| --- | --- |
| `color-scheme` 宣言なし（light-only 扱い） | 白 |
| `color-scheme: light dark` / `dark` を宣言 | ダーク（WebKit は概ね `#1E1E1E`） |

ブラウザはダーク対応を名乗っていないページを勝手にダーク背景へ置かない。befold はそれを無視して全ページへダークキャンバスを適用している。なお `ViewerTheme.swift:12` のコメントにあるとおり `#1E1E1E` はもともと WebKit の Canvas 相当値。

## 方針

独自のデフォルト CSS を注入するのではなく、**HTML 文書にはキャンバスごと明け渡す**（＝ WebKit の既定動作の上書きをやめる）。これなら分岐ロジックを持たずに両ケースが成立する。

## 検討すべき点

1. ダークウィンドウの中に白い矩形が出る見え方になる（ブラウザ相当だが他形式と見た目が揃わない）
2. `drawsBackground` は Markdown 等と同一 WebView で共有する設定のため、直接 HTML モードの出入りに合わせた切り替えが要る（共通経路の不変条件に触る）
3. iframe/srcdoc 経路にも同じ手当てが要る
4. `BefoldApp/BefoldKit/Resources/style.css:1-8` と `ViewerTheme.swift` の「キャンバス色はネイティブが唯一の定義」というルールに、HTML だけは文書が所有するという例外の明記が要る

## 未実測の前提

「WKWebView で `drawsBackground` を戻せば `color-scheme` に応じて白／ダークを塗り分ける」は未検証。`color-scheme` 宣言あり／なしのサンプル 2 本を用意して実機で確認すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `color-scheme` を宣言していない HTML（背景未指定・暗い文字色）が、OS ダークモードで白背景に描画され読める
- [x] #2 `color-scheme: light dark` を宣言した HTML が、OS ダークモードでダーク背景に描画される
- [x] #3 直接ロード経路（本体アプリ）と iframe/srcdoc 経路（QuickLook 等）の両方で上記が成立する
- [x] #4 HTML から他形式（Markdown 等）へ切り替えた後、キャンバスが従来どおり `ViewerTheme.canvas` に戻る
- [x] #5 `style.css` 冒頭と `ViewerTheme.swift` の設計コメントに HTML の例外が明記されている
- [x] #6 実装着手前に `/review-design` を回し、結果を Implementation Plan に反映している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果（実施済み）

チェックリスト 10 項目のうち、該当したのは項目 2 / 3 / 5 / 7 / 9。項目 1・4・6・8・10 は非該当（判定は `isActive` / `fileType` という事実で行い、ユーザーに見せる新状態は増えず、高頻度経路に乗らず、非同期の世代管理は不要、型グループは `DirectHTMLModeController` 169 行 / `ViewerWebViewFactory` 134 行 / `ViewerTheme` 17 行に数行追加のみでプロトコル準拠・stored property・注入クロージャは増えない）。

## 手順

### 1. 方式の確定（実測が先。これを飛ばさない）

`color-scheme` 宣言あり／なしのプローブ HTML 2 本を用意し、次の 2 つの未検証の前提を実測してから方式を決める。

- (a) `drawsBackground` を戻すと WebKit が `color-scheme` に応じて白／ダークを塗り分けるか
- (b) iframe/srcdoc の子文書が透過なのは `drawsBackground=false` の伝播が原因か

**(b) が iframe 側の直し方を左右する。** 伝播が原因なら、iframe 要素へ `background: white` を置く素朴な直し方は `color-scheme: dark` を宣言した子文書で逆に壊れるため採れない。

測り方の候補: `WKWebView.takeSnapshot` で実描画ピクセルを取る（メモリ `webview-css-snapshot-harness` の独立ハーネス方式）。ユニットテストでは実描画色を測れないため、この 1 点は実機確認とその記録に頼る。結果は Implementation Notes に残す。

### 2. 直接ロード経路（本体アプリ）

`drawsBackground` の反転を `allowsContentJavaScript` と**同じ層・同じ場所**に置く。

- 現在: `BefoldApp/BefoldRenderKit/ViewerWebViewFactory.swift:87-88` で全経路に `false` を強制
- enter 側: `DirectHTMLModeController.enter`（同 :75 で `allowsContentJavaScript = false` を設定している場所）
- exit 側: `ViewerRenderer+RenderHelpers.swift:53-66` の `reloadViewerHTML`（`allowsContentJavaScript = true` へ戻している場所）

**`RenderedStateMirror` には載せない。** `RenderedStateMirror.swift:12-24` のフィールドは `ContentUpdatePlanner` の再描画要否判定へ自動参加するため、載せると背景モードが再描画のトリガーになってしまう。`allowsContentJavaScript` / `appliedPageZoom` / `readiness` と同じく「ミラーの外だが enter/exit とセットで倒す状態」として扱う。判定に使うのは既存の `isActive` そのもので、新しい状態も述語も増やさない。

切り替えのタイミング（exit 時に viewer.html の再ロード完了の前に戻すか後に戻すか）を選び、理由をコメントに残す。前なら一瞬ウィンドウ色、後なら白が一瞬残る。

### 3. iframe/srcdoc 経路（QuickLook ほか）

`BefoldApp/viewer-src/renderers.ts:111-134` の `_renderHtml`。手順 1 の (b) の実測結果に従って方式を決める。

QuickLook では前提自体が成立していない点に注意する。`window.backgroundColor = ViewerTheme.canvas` は `BefoldApp/befold/App/ViewerWindowChrome.swift:31-33` = **アプリ本体のみ**で、QuickLook（`BefoldQuickLook/PreviewViewController.swift:11` の `OneShotRenderer(features: .quickLookRestricted)`）は背景色を設定せず QL パネルの地色が透けている。

`.viewer` に `padding: 32px`（`BefoldKit/Resources/style.css:125-132`）があるため、iframe に背景を与えると左右 32px だけキャンバス色が残り「縁」に見える。実機で確認して許容するか詰める。

### 4. 見た目の確認（F3）

`ViewerWindowChrome.swift:35-37` が `titlebarAppearsTransparent = true` / `titlebarSeparatorStyle = .none` のため、ダークのタイトルバーの真下に白い本文が境界線なしで接する。**まず実機で見てから**セパレータの要否を決める。先回りで分岐を入れない。

### 5. 担保

既存テスト `directHTMLExitDiscardsEntireMirror`（`BefoldApp/befoldTests/ViewerRendererContentUpdateTests.swift:20-39`）はミラーしか見ないため背景をカバーしない。enter / exit 後に `webView.value(forKey: "drawsBackground")` を確認するテストを足し、破れたら落ちる状態にする。

### 6. ドキュメント

`BefoldApp/BefoldKit/Resources/style.css:1-8` と `BefoldApp/befold/Viewer/ViewerTheme.swift` の「キャンバス色はネイティブが唯一の定義」という設計コメントに、**HTML 文書だけは canvas ごと文書が所有する**という例外と理由（ブラウザの `color-scheme` 意味論に合わせる）を明記する。実装完了時に `docs/dev/native-app-design.md` へも追随させる。

## スコープの決定

- QuickLook / iframe 経路も本タスクで直す（同じ原因の同型バグを片方だけ直さない）
- タイトルバーのセパレータは実機で見てから判断する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 採用した方針

「HTML 文書には canvas ごと明け渡す」（＝ WebKit の既定動作の上書きをやめる）。独自のデフォルト CSS の注入は採らなかった。

## 実測（`WKWebView.takeSnapshot` のピクセル / ダークアピアランス）

設計レビューで挙げた 2 つの未検証の前提を、専用プローブで測って決着させた。

| 条件 | 実測 |
| --- | --- |
| `drawsBackground=false`（従来） | `a=0.00`（WebView は塗らない）→ ダークキャンバスが透ける |
| `true` / `color-scheme` 宣言なし | `#FFFFFF` |
| `true` / `color-scheme: light dark` または `dark` | `#282828` |
| `true` / iframe の srcdoc 子文書 | **子自身の宣言**に従い白 / `#282828` を塗り分ける |
| `false` / iframe 要素に `background: white` | 子が `dark` 宣言でも白（＝子の宣言が届かない） |
| `false` / iframe 要素に `background: Canvas` | 子が宣言なしでも `#282828`（＝親の宣言に従う） |

## 計画からの単純化

最後の 2 行が示すとおり、**透過のままでは CSS で正しく直せない**（どちらの当て方も逆のケースを壊す）。一方 `drawsBackground=true` にすると iframe の子文書も自分の `color-scheme` に従うため、**計画の手順 3（iframe 経路の CSS 変更）は丸ごと不要**になった。`renderers.ts` と `style.css` のルールには一切手を入れていない。

## 実装

判定と適用を `ViewerWebViewFactory` の 2 つの static に集約し（KVC はここ 1 箇所）、直接ロード経路と iframe 経路の両方が同じ判定を共有する。

- `documentOwnsCanvas(fileType:isSourceMode:)` … `fileType == .html && !isSourceMode`
- `setDocumentOwnsCanvas(_:on:)` … 実測値を doc コメントに記録
- `DirectHTMLModeController.enter` で明け渡し、`ViewerRenderer.reloadViewerHTML` で透過へ戻す（`allowsContentJavaScript` と同じ層・同じ場所。**`RenderedStateMirror` には載せない** — 載せると `ContentUpdatePlanner` の再描画要否判定に自動参加してしまうため）
- `OneShotRenderer.load`（QuickLook 等）でも同じ判定を適用

新しい状態も述語も増えていない（判定は既存の `fileType` / `isSourceMode` という事実そのもの）。

## 設計レビュー（/review-design）の結果と対応

- F1（消費経路の全列挙）→ 直接ロードと iframe の両経路に適用。QuickLook は `ViewerWindowChrome` を通らずウィンドウ背景を持たない（QL パネルの地色が透ける）ため同じ壊れ方をしていた
- F2（未実測の前提）→ 上表のとおり実測して方式を確定
- F3（タイトルバー直下に白が接する）→ 実機で確認し、気にならないためセパレータは入れない（先回りの分岐を足さない）
- F5（担保）→ 既存の `directHTMLExitDiscardsEntireMirror` はミラーしか見ず背景をカバーしないため、専用テストを追加

## 検証

- 新規テスト 4 本（`ViewerCanvasOwnershipTests` 3 本 + `ViewerRendererOneShotIntegrationTests` 1 本）
- **修正を戻すと落ちることを実測**: `直接HTMLモードへ入るとcanvasを文書へ明け渡す` / `直接HTMLモードから復帰するとcanvasは透過へ戻る` / `loadOneShot はHTML文書のときだけcanvasを文書へ明け渡す` の 3 本が失敗（`Expectation failed: drawsBackground(...)`）。戻した後は再度パス
- `swift test` 全 1607 件パス
- swiftlint: origin/main とのベースライン差分ゼロ（真の新規・解消ともに空。件数 54 → 54）
- `xcodebuild build -scheme befold` 成功
- 実機: ダークモードで `sample/sample.html` が白背景・黒文字で読めることをユーザーが確認

## 責務

`ViewerWebViewFactory` に static 2 つを足しただけで、型・プロトコル準拠・stored property・注入クロージャのいずれも増えていない（`scripts/check-type-group-size.sh --check` も閾値以内）。このため `responsibility-reviewer` は起動していない。

## 現在仕様への反映

`docs/dev/native-app-design.md` を更新した（`ViewerTheme` の行に例外を追記し、レンダリング節に「キャンバス（地）の所有者」の項を新設）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
外部の HTML 文書だけ canvas（地）を文書に所有させ、ブラウザと同じ color-scheme 意味論に戻した。

原因は所有権の分割だった。befold は HTML の前景色（文字色）を文書に委ねる一方、背景は `ViewerWebViewFactory` の `drawsBackground=false` でダークキャンバスのまま保持していたため、明るい背景を前提に文字色だけを指定した HTML（`sample/sample.html` の `color: #24292f` / 背景指定なし）がダークモードで読めなくなっていた。

判定 `documentOwnsCanvas(fileType:isSourceMode:)` と適用 `setDocumentOwnsCanvas(_:on:)` を `ViewerWebViewFactory` に集約し、直接ロード経路（`DirectHTMLModeController.enter` / `ViewerRenderer.reloadViewerHTML`、`allowsContentJavaScript` と同じ層）と iframe 経路（`OneShotRenderer`、QuickLook 等）の両方が共有する。新しい状態も述語も増やしていない。

`WKWebView.takeSnapshot` の実測で、`drawsBackground=true` にすると iframe の srcdoc 子文書も**子自身の** `color-scheme` 宣言に従って塗り分けられることが分かったため、計画にあった iframe 経路の CSS 変更は不要になり `renderers.ts` / `style.css` のルールには手を入れていない（逆に透過のままでは、親側に `background: white` を当てても `Canvas` を当てても、どちらかのケースが壊れることも実測で確認した）。

検証: 新規テスト 4 本を追加し、修正を戻すと 3 本が落ちることを実測。`swift test` 全 1607 件パス、swiftlint はベースライン差分ゼロ（54 → 54）、`xcodebuild` 成功、ダークモードでの実機表示をユーザーが確認。`docs/dev/native-app-design.md` に「キャンバス（地）の所有者」を追記した。
<!-- SECTION:FINAL_SUMMARY:END -->
