---
id: TASK-429
title: AppDelegate（495 行）を責務ごとに分割する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 12:35'
updated_date: '2026-08-11 23:30'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 100400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/App/AppDelegate.swift` は 495 行（`wc -l` 実測、2026-08-10 時点）で `BefoldApp/.swiftlint.yml:13-15` の `file_length` warning 400 を超えている。TASK-428 のラチェットを最終的に撤去して単純な閾値強制へ畳むには、この負債の返済が必要。

分割の作法はプロジェクト既定の `Type+Feature.swift` extension、または独立型への切り出し（前例: `SidebarNavigator` / `ViewerToolbarController`）。ただし TASK-411 の Description が記録しているとおり、行数上限の回避だけを目的とした extension 分割は責務の分離にならない。凝集単位で切ること。

着手時に確認すべき制約: `AppDelegate` は `NSApplicationDelegate` 準拠であり、プロトコル準拠メソッドはレスポンダチェーン／フレームワークから呼ばれるため静的な呼び出し元を持たない（`.claude/CLAUDE.md` の「知識グラフの Swift での限界」節）。移動可否はグラフではなく実コードで判断する。また Sparkle 2 の `SPUStandardUpdaterController` を保持している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 AppDelegate の型グループ（AppDelegate.swift + AppDelegate+*.swift の合算）が 400 行以下になる（scripts/check-type-group-size.sh で実測）
- [x] #2 分割が行数回避ではなく責務単位になっている（各分割先が何を担うかを 1 行で言える）。extension 分割ではなく独立型への切り出しで行う
- [x] #3 scripts/type-group-baseline.txt が --update-baseline で締め直され、空いた行数枠が再肥大に使えない状態でコミットされている
- [x] #4 main との swiftlint 差分に真の新規が無い（/swiftlint-baseline の手順で確認）
- [x] #5 swift test が既存どおり通る
- [x] #6 新規ファイル追加後に xcodegen generate 済みで xcodebuild build が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
0. 前提: 型グループ実測 562 行(本体 495 + +HostedPanels 67)。ラチェット(CI: .github/workflows/ci.yml:80-103)はグループ合算で判定するため、extension 分割では 1 行も減らない。よって独立型への切り出しで行う。
1. composition root に activeViewer: () -> ViewerWindowController? を 1 本作り、切り出し先へ注入する(NSApp.mainWindow を読む判断を 3 箇所へ複製しない。Quick Open パネルが canBecomeMain=false という不変条件の定義点を 1 つに保つ)。
2. AppCLIRequestReceiver を新設し、DistributedNotificationCenter 購読 + ACK 返送 + requestID 重複排除 + open/bookmark の振り分けを移す。**AppDelegate.init 内で eager に生成する**(現状の購読は init 内 = applicationWillFinishLaunching より前。didFinishLaunching へ倒すと起動直後の CLI 要求で ACK が落ちて再送待ちになる)。
3. CLIShimCoordinator を新設し、notifyIfCLIShimIsStale / CLI 設置 / presentInstallResult を移す。@objc installCLI は薄い転送として AppDelegate に残す。
4. DocumentOpener を新設し、openViewer 3 種 / openPaths / openSequentially / presentNoFileAlert / showOpenPanel を移す。AppDelegate.shared?.openViewer(DocumentController.swift:10, ViewerWindowController.swift:253)は薄い転送で維持する。
5. QuickOpenCoordinator を新設し、QuickOpenPanelController の保持 / makeQuickOpenEnvironment / openFromQuickOpen を移す。gitFileIndex は必須引数で渡す(デフォルト引数にすると渡し忘れが別インスタンスになりコンパイルでは落ちない)。
6. AppUpdaterController を新設し、SPUStandardUpdaterController の保持 / start / feedURLString を移す。updaterDelegate は weak(Sparkle/SPUStandardUpdaterController.h:85)なので、この型を AppDelegate が strong に保持する。
7. 移した先から見えなくなる private stored property(sessionStore / sidebarDisplayPreference / recentDocumentsStore / bookmarkStore ほか)は internal へ上げるのではなく引数で渡す。
8. xcodegen generate → swift build → swift test → xcodebuild build。
9. scripts/check-type-group-size.sh で 400 以下を実測し、--update-baseline でベースラインを締め直してコミットする(CI は減少を warning で通すため、締め直さないと空いた枠へ再肥大できてしまう)。
10. /swiftlint-baseline で main との差分に真の新規が無いことを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手前に /review-design を実施。方針を変える指摘 4 件: (a) AC #1 がファイル単位で、ラチェットが見る型グループを測っていない → AC を型グループ 400 以下へ改訂、(b) baseline を締め直さないと 162 行分の再肥大がグリーンで通る → AC 追加、(c) activeViewerController が 3 箇所へ複製される → 注入で定義点を 1 本化、(d) CLI 受信の購読を init より後ろへ倒すと起動直後の ACK が落ちる。該当しない項目: 判定の真実の源 / 不変条件 / 新状態の表示 / 非同期の世代管理(振る舞い不変のリファクタで述語・状態・非同期経路を増やさない)、高頻度経路(validateMenuItem は AppDelegate に残し不変)。

検証（すべて実測）:
- 型グループ: scripts/check-type-group-size.sh で 562 → 351 行（AppDelegate.swift 284 + AppDelegate+HostedPanels.swift 67）。--over の出力から AppDelegate が消え、ベースラインからも該当行が削除された。--check は exit 0、--self-test も OK。
- swiftlint: /swiftlint-baseline 手順（git archive origin/main を別ディレクトリへ展開して比較）。真の新規 0 件。解消 2 件（AppDelegate.swift の file_length / type_body_length）。
- swift test: 1430 tests / 211 suites すべて passed、失敗 0。
- xcodegen generate 後 xcodebuild build -scheme befold: BUILD SUCCEEDED。
- markdownlint-cli2: 0 issues。scripts/check-doc-symbols.sh: exit 0。

途中経過: 最初の分割（5 型）では 417 行で 400 に届かず、メニュー配線を MainMenuCoordinator へ追加で切り出した。その時点で swiftlint に真の新規 2 件（init 51 行の function_body_length / makeWindowManager 7 引数の function_parameter_count）が出たため、閾値回避ではなく AppStores（アプリ全体で共有するストアの束）を新設して構造的に解消した。副産物として「全体で 1 個ずつ共有」が束を配る形で構造として保たれる（TASK-319 型の事故に対する担保）。

設計レビューで挙げた 4 点の着地:
(a) AC をファイル単位から型グループ単位へ改訂済み。(b) baseline を --update-baseline で締め直し、AppDelegate の 562 行エントリを削除。(c) ActiveViewerProvider.fromMainWindow に定義点を 1 本化し、AppDelegate / DocumentOpener / QuickOpenCoordinator の 3 者へ注入。(d) AppCLIRequestReceiver を AppDelegate.init 内で eager 生成し、購読タイミングを維持。

予告どおり private のファイルスコープに 1 回当たった（AppDelegate+HostedPanels が stores.codeFontPreference を読むため stores を internal へ）。doc コメントで「読んでよいのは同じ型グループの extension だけ」と明示した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppDelegate の型グループ 562 行を、責務ごとの独立型 8 件（AppStores / ActiveViewerProvider / DocumentOpener / MainMenuCoordinator / QuickOpenCoordinator / AppCLIRequestReceiver / CLIShimCoordinator / AppUpdaterController）へ切り出して 351 行にした。extension 分割はラチェットの合算判定で無効なため独立型で行い、AppDelegate にはライフサイクルと @objc アクションの転送だけを残した。scripts/type-group-baseline.txt を締め直して空いた枠が再肥大に使えないようにし、docs/dev/native-app-design.md の構成図・コンポーネント表・自動アップデート節を実態へ追随させた。検証: 型グループ 351 行（--check exit 0）、swiftlint 真の新規 0 件・解消 2 件、swift test 1430 tests 全通過、xcodebuild BUILD SUCCEEDED、markdownlint 0 issues。
<!-- SECTION:FINAL_SUMMARY:END -->
