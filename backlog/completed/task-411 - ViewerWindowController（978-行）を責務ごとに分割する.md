---
id: TASK-411
title: ViewerWindowController（978 行）を責務ごとに分割する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 07:25'
updated_date: '2026-08-10 09:45'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 500000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/befold/App/ViewerWindowController.swift は 978 行（wc -l 実測）で、BefoldApp/.swiftlint.yml の file_length error（1000）まで残り 22 行しかない。SwiftLintPlugins はビルドステップで走るため、この上限に達した時点でビルドが error severity で落ちる。

1 つの型が次をすべて所有している: ウィンドウクロム、スプリットビュー構築、サイドバー/ツールバーのホスティング、WebView コマンド配線、ファイル単位の永続化、表示モード遷移、スクロール/ズームの記録、参照解決、ペーストボード、メニュー検証。加えて 5 つのプロトコル準拠（SidebarNavigatorHost / ViewerRendererDelegate / ReferenceResolutionHost / ViewerToolbarHost / NSWindowDelegate）を兼ねる。すでに +Capabilities / +Diff / +WindowHelpers の 3 拡張が存在するが、これは同じ行数上限を回避するために切られたものであり責務の分離にはなっていない。

init も 199-333 行（非コメント 86 行）で function_body_length の warning 50 を超過しており、error 100 まで 14 行。ストア構築・サイドバーナビゲータ・NSWindow とクロム・ツールバーコントローラ・WebViewCommandController・スプリットビュー・フレーム復元・スワイプモニタ・ストアコールバック配線・表示モード復元・提示開始という 11 の工程が順序制約つきで並んでおり、順序制約はコメント 8 個で説明されている。

ViewerToolbarController / SidebarNavigator が既に独立オブジェクトになっている前例があるので、残りのプロトコル準拠も同じ形へ寄せられる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ViewerWindowController.swift が file_length warning の 400 行以下になる
- [x] #2 init のボディが function_body_length warning の 50 行以下になる
- [x] #3 +Capabilities / +Diff / +WindowHelpers の 3 拡張が、行数回避ではなく責務単位の分割として再編される（または独立型へ移る）
- [x] #4 main との swiftlint 差分に「真の新規」が無い（/swiftlint-baseline の手順 4 で確認。既存違反の解消は可）
- [x] #5 swift test が既存どおり通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 前提（実測・コード参照）

- ViewerWindowController.swift は起票時 978 行 → **現在 993 行**（file_length error 1000 まで残り 7 行）
- main 側 swiftlint ベースライン 77 件。うち当該ファイルに 4 件
  （file_length 993>400 / function_body_length init 86>50 / type_body_length 285>250 / opening_brace）
- swift test ベースライン: 1369 tests / 198 suites すべてパス
- 分割の作法はプロジェクト既定の `Type+Feature.swift` extension（前例: SidebarNavigator 本体 364 行 + 責務名の拡張 4 本）

## 動かせないもの（分割の制約）

1. **@objc メニューアクション 13 個と validateMenuItem は ViewerWindowController 自身に残す**
   （レスポンダチェーン。プロダクト側 `#selector(ViewerWindowController.x)` が 14 箇所、
   MainMenuBuilderTests が 10 箇所）。extension への移動は可、別クラスへの移動は不可。
2. `@objc performReferenceMenuAction(_:)` も残す
   （ViewerWindowControllerTests.swift:571 が `Selector((\"performReferenceMenuAction:\"))` で perform する）。
3. テストが触る internal 面は現状維持（store / sidebar / toolbarController / referenceCoordinator /
   webViewProxy / fileListModel / fileURL / capabilities / displayMode ほか約 40 メンバ）。
   実装を移す場合も同名で到達できること。
4. ViewerWindowManager / AppDelegate から呼ぶ公開 API も現状維持。

## 分割方針

### 独立型へ移す（状態ごと移動し、単体テスト可能にする）

- **`ViewerWindowChrome`（新規）** ← `+WindowHelpers.swift` 全部 + init のウィンドウ構築 30 行
  - makeWindow(fileURL:) / applyURL(_:to:) / applyInitialFrame(...) / offsetToAvoidOverlap(_:)
  - `+WindowHelpers` はこれで消滅（AC#3 の 1 本目）
- **`ViewerCapabilities` へ導出を移す** ← `+Capabilities.swift`
  - `ViewerCapabilities(store:fileURL:isPreviewingFolder:isDirectHTMLMode:)` の形にし、
    コントローラ側は 1 行の computed property にする
  - `+Capabilities` はこれで消滅（AC#3 の 2 本目）

### 責務名の extension へ再編（`Type+Feature.swift`）

- `+DiffPresentation.swift` ← `+Diff.swift` を改名。`validateDisplayModeItem` は
  差分の責務ではないので `+MenuActions` へ移す。doc の「行数上限を超えないよう分けている」を
  責務の説明へ書き換える（AC#3 の 3 本目）
- `+Presentation.swift` ← 表示モード遷移・スクロール位置の退避/復元・提示開始（現「Source Mode」節）
- `+MenuActions.swift` ← @objc アクション 13 個 + validateMenuItem + validateDisplayModeItem
- `+WindowDelegate.swift` ← NSWindowDelegate + saveWindowFrame
- `+FileNavigation.swift` ← switchFile / performFileSwitch / handleRename / navigateToFolder /
  navigateHistory / focusWindow / setSidebarCollapsed
- `+ContentAssembly.swift` ← makeSplitViewController + ハンドラ生成 + wireStoreCallbacks
- `+SidebarHost.swift` / `+Renderer.swift` / `+References.swift` ← 各プロトコル準拠
- `ViewerWindowControllerDelegate.swift` ← delegate プロトコル + FileSwitchOutcome

### 本体に残すもの

型 doc・stored property・init・init(coder:)。init は工程ごとのヘルパー
（makeWindow / makeSidebarNavigator / makeWebViewCommands / wireAfterWindowCreation）へ
畳んで body 50 行以下にする。

## 併せて処理する

- `canToggleSourceMode`（VWC:797-799）は product・test 双方から未参照のため削除する
  （判定は capabilities.canToggleSourceMode 側に一本化済み）
- `private` → `internal` へ上げる stored property には「どの拡張が触ってよいか」を doc で明記する
- FeatureGate 参照の移動に伴い **`.swiftlint.yml` の allowlist と `FeatureGate.swift` の doc の
  両方**を更新する（`makeChangedFilesOnlyToggle` → +ContentAssembly、`+Diff` → `+DiffPresentation`）
- ADR 0002「実装状況」節が `ViewerWindowController.beginPresentingDocument` / `setDisplayMode` を
  名指ししている（docs/adr/0002-...md:271-279）。所在が変わるなら追随させる
- docs/dev/native-app-design.md のコンポーネント表へ `ViewerWindowChrome` を追加する
- 新規ファイル追加後に `xcodegen generate`

## 検証

1. `swift build`
2. `swift test`（1369 件が同数パス）
3. `/swiftlint-baseline`（真の新規ゼロ。当該 4 件が「解消したもの」に出る想定）
4. `wc -l` で本体 400 行以下・init body 50 行以下を実測

## /review-design の結果（実施済み）と反映

指摘 8 件のうち 6 件を方針へ反映した。

1. **能力導出を `ViewerCapabilities` へ移すのは取りやめる**（C）。現在の導出は
   `supportsDiffDisplay` だけが `FileType(url:)` を使い、他 3 つは `store.fileType` を使う
   （TASK-338 の理由付き）。イニシャライザに store と URL を両方入れると
   「1 行だけ入力が違う」形になり、揃えたくなる圧力がむしろ増す。
   `ViewerCapabilities` は `import Foundation` だけの純粋な値型のまま残す。
   `+Capabilities.swift` は「能力の面」の責務ファイルとして残し、`canSelect(_:)` を集約する。
2. **`offsetFrameToAvoidOverlap` は `ViewerWindowChrome` に入れない**（F-1）。
   `NSApp.windows` を走査して `ViewerWindowController` を判定する＝「他のビューア窓を知る」処理で、
   器の責務ではない。Chrome は `isOccupied: (NSPoint) -> Bool` を引数で受け、
   述語はコントローラ側が供給する（Chrome が ViewerWindowController を知らずに済む）。
3. **ツールバーの生成・delegate 設定・window への取り付けを `ViewerToolbarController.init` へ内包**（A-3）。
   3 手順の順序制約（delegate 設定前に代入するとアイテムが空）を破れない構造にし、init も 4 行減る。
4. **@objc アクションの置き場所の規則を明文化**（F-2）。
   メインメニュー/ツールバー由来のアクションと validateMenuItem は `+MenuActions`
   （`toggleDiffLayout` を含む）。その場で組み立てるコンテキストメニューのアクション
   （`performReferenceMenuAction`）はメニューを作る側と同居させる（`+References`）。
5. **`private` → `internal` 昇格の担保**（B）。`beginPresentingDocument` /
   `saveScrollPositionBeforeTransition` は分割で internal になる。ADR 0002 の
   「保存値を読むのは提示開始の 3 契機だけ」を守っていたのは doc ではなく private だったため、
   **呼び出し元の個数をソース走査で固定するテスト**を同じタスクで足す
   （`FeatureGateEnumerationTests` と同じ走査方式）。
6. **FeatureGate の同期範囲を再算出**（D）。`makeSidebarGitStatusLoader` も移すため
   `ViewerWindowController.swift` は `FeatureGate.` を含まなくなる。
   allowlist と FeatureGate doc の**両方から削除**し、`+Assembly` / `+DiffPresentation` を追加する。
7. 組み立て系の拡張は `+ContentAssembly` ではなく **`+Assembly`**（ビュー構築だけでなく
   ストア購読・スワイプ監視の配線も含むため）（F-3）。
8. `canToggleSourceMode` は capabilities 版と**判定条件が違う**（フォルダー提示中の扱い）。
   統合ではなく削除であることを Implementation Notes に残す（G）。

反映しなかったもの: A-2 のうち「window.delegate 設定タイミング」「wireStoreCallbacks → openFile」の
2 テストは、当該工程を init に 1 行ずつ残す方針のため脆さが増えない（現状維持）。
`applyDisplayMode → beginPresentingDocument` の順序は 5 の走査テストで代替する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実測（検証）

- `ViewerWindowController.swift` 993 行 → **249 行**（AC#1）
- init のボディ 87 行 → **39 行**（非コメント行を実測。swiftlint の
  function_body_length 警告も消滅）（AC#2）
- `swift build` / `xcodebuild build -scheme befold` ともに成功（警告なし）
- `swift test`: **1371 tests / 199 suites パス**（着手前ベースラインは 1369 / 198。
  差の 2 件は今回追加したトリップワイヤ）（AC#5）
- swiftlint: main 77 件 → 73 件。`/swiftlint-baseline` 手順 4 の
  **「真の新規」は空**、「解消したもの」は当該ファイルの 4 件
  （file_length / function_body_length / type_body_length / opening_brace）（AC#4）
- markdownlint-cli2: 0 issues / `scripts/check-doc-symbols.sh`: 指摘なし

## 分割の結果（AC#3 の内訳）

既存 3 拡張の扱い:

- `+WindowHelpers.swift` → **消滅**。独立型 `ViewerWindowChrome`（90 行）へ移した。
  NSWindow の生成・外観・タイトル追従・初期フレーム決定だけを持ち、文書の状態も
  他の窓も知らない。重なり判定は `isOccupied: (NSPoint) -> Bool` で受け取るため
  `NSApp` にも `ViewerWindowController` にも依存しない
- `+Diff.swift` → `+DiffPresentation.swift` へ改名し**再スコープ**。
  差分の責務ではない `validateDisplayModeItem` を `+MenuActions` へ移し、
  「行数上限を超えないよう extension に分けている」という doc を責務の説明へ書き換えた
- `+Capabilities.swift` → **能力の面として完成させた**。同じ責務なのに離れていた
  `canSelect(_:)` を集約し、未参照だった `ViewerWindowController.canToggleSourceMode` を削除

新規ファイル: `ViewerWindowChrome` / `ViewerWindowControllerDelegate` と、責務名の拡張 9 本
（`+Assembly` / `+FileNavigation` / `+Presentation` / `+DiffPresentation` / `+MenuActions` /
`+References` / `+SidebarHost` / `+Renderer` / `+WindowDelegate`）。

## 決めたことと、それを守らせるもの

- **「保存値を読むのは提示開始の 3 契機だけ」（ADR 0002）**: 分割前はこの規則を
  同一ファイル内の `private` が担保していた。拡張へ出して internal になったため、
  `ViewerWindowPresentationEntryPointTests` が `beginPresentingDocument` と
  `saveScrollPositionBeforeTransition` の**呼び出し元の個数をソース走査で固定**する
  （`FeatureGateEnumerationTests` と同じ方式）。ADR 0002 の実装状況節にも追記した
- **ツールバーの 3 手順の順序制約**（生成 → delegate 設定 → window への取り付け）は
  `ViewerToolbarController.init` の中へ閉じた。呼び出し側で 3 行に並べると順序を
  入れ替えてもコンパイルが通るため、破れない構造へ変えた
- **init の工程の順序**は畳まずに 1 行ずつ残した。中身だけを `+Assembly` へ移し、
  「なぜその順か」のコメントは init 側に残してある

## 判断の記録

- `ViewerCapabilities` へ能力導出を移す案は**採らなかった**。`supportsDiffDisplay` だけが
  `FileType(url:)` を使い（TASK-338: `store.fileType` は非同期ロード完了まで旧ファイルの値を
  保つ）、他 3 つは `store.fileType` を使う。1 つのイニシャライザに store と URL を
  両方入れると「1 行だけ入力が違う」形になり、揃えたくなる圧力が増す。
  `ViewerCapabilities` は `import Foundation` だけの純粋な値型のまま残した
- `ViewerWindowController.canToggleSourceMode` は **統合ではなく削除**。
  `ViewerCapabilities.canToggleSourceMode` とは判定条件が違う
  （旧: `store.fileType.supportsSourceMode && !store.isRejected` /
  capabilities 版: `onDocument && supportsSourceMode` でフォルダー提示中の扱いが異なる）。
  参照が 0 だったため、条件の統合ではなく単純に消した
- 未使用だった stored property `defaults` / `sidebarDisplayPreference` も削除した
  （どちらも init 内でパラメータとしてしか使われていなかった）
- `FeatureGate` の同期は 2 箇所とも更新した。`makeSidebarGitStatusLoader` も移したため
  `ViewerWindowController.swift` は allowlist から**削除**し、`+Assembly` と
  `+DiffPresentation` を追加（`FeatureGateEnumerationTests` がパスすることで確認）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowController.swift（993 行）を責務ごとに分割し、249 行にした。独立型 ViewerWindowChrome（NSWindow の器）と ViewerWindowControllerDelegate を切り出し、残りを責務名の extension 9 本（+Assembly / +FileNavigation / +Presentation / +DiffPresentation / +MenuActions / +References / +SidebarHost / +Renderer / +WindowDelegate）へ再編。行数回避で切られていた +WindowHelpers は独立型へ吸収して消滅、+Diff は +DiffPresentation へ再スコープ、+Capabilities は canSelect を集約して能力の面として完成させた。init は工程の順序と理由コメントを残したまま中身をヘルパーへ移し 87 行 → 39 行。分割で private を失った提示開始経路（ADR 0002）は ViewerWindowPresentationEntryPointTests がソース走査で呼び出し元の個数を固定する。ツールバーの 3 手順の順序制約は ViewerToolbarController.init へ内包して破れない構造にした。検証: swift build / xcodebuild 成功、swift test 1371 件パス（ベースライン 1369 + 新規 2）、swiftlint の真の新規ゼロ（77 → 73 件、当該ファイルの 4 件が解消）。
<!-- SECTION:FINAL_SUMMARY:END -->
