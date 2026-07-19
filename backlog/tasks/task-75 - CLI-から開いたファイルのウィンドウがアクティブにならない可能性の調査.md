---
id: TASK-75
title: CLI から開いたファイルのウィンドウがアクティブにならない可能性の調査
status: To Do
assignee:
  - '@claude'
created_date: '2026-07-19 11:54'
updated_date: '2026-07-19 13:55'
labels: []
dependencies: []
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
既に他のウィンドウが開いている状態で CLI（`open -a befold <file>` 経由の
シム、AppDelegate.application(_:open:) → ViewerWindowManager.openViewer）から
新しいファイルを開いたとき、指定したファイルのウィンドウが必ずしも
アクティブ（キーウィンドウ・最前面）にならない可能性がある。原因調査を行う。

関連コード:
- App/AppDelegate.swift: application(_:open:)（複数 URL を受け取る経路）
- App/ViewerWindowManager.swift: openViewer(for:forceSidebarVisible:)
  （新規ウィンドウは showWindow(nil) 後に NSApp.activate() を呼んでいるが、
  複数ファイル同時オープン時やアプリが既にアクティブな場合の前面化タイミングは
  未検証。既存ファイルの場合は makeKeyAndOrderFront を呼んでいる）

TASK-73（CLI オプション拡充）で複数ファイル/フォルダを複数ウィンドウで開く
機能を実装する際にも影響しうるため、先行して原因を切り分ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 既存ウィンドウがある状態で CLI から1ファイルを開いたとき、対象ウィンドウがアクティブになるかどうかの再現条件を明確化する
- [x] #2 複数ファイルを同時に CLI から開いた場合に、どのウィンドウがアクティブになるか（あるいはならないか）を明確化する
- [x] #3 他アプリがアクティブな状態から CLI 経由で開いた場合と、befold 自体が既にアクティブな状態から開いた場合の挙動差を明確化する
- [x] #4 原因（NSApp.activate() のタイミング、非同期ウィンドウ生成、Space をまたぐ場合の挙動など）を切り分けて記録する
- [x] #5 調査結果を踏まえた対応方針（修正が必要か、TASK-73 側で扱うべきか等）を記録する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 調査結果 (コードリーディング)

### 経路の確定
CLI (`open -a befold <file>`) → `AppDelegate.application(_:open:)` が `urls: [URL]` を1回受領 → `for url in urls { openViewer(for:) }` を**同期ループ** → `ViewerWindowManager.openViewer(for:forceSidebarVisible:)`。
- 新規: `NSApp.activate()` → `controller.showWindow(nil)`（ViewerWindowController は showWindow 未オーバーライド = 標準 NSWindowController の makeKeyAndOrderFront が走る）
- 既存(同一ファイル): `NSApp.activate()` → `existing.window?.makeKeyAndOrderFront(nil)`
- **open 経路に Task/DispatchQueue 等の非同期は一切なし**（asyncAfter は applicationDidFinishLaunching の Space 救済のみで open とは無関係）。よってウィンドウ生成・前面化は決定論的。

### AC#1 単一ファイル・既存ウィンドウあり
別ファイルが開いている状態で新ファイルを CLI で開く=新規ブランチ。activate 後 showWindow で対象が key/front になる。同一ファイル再オープンは既存ブランチで makeKeyAndOrderFront。いずれも同期で、通常(open コマンドに伴う activation 付与がある)ケースでは対象ウィンドウがアクティブになる。失敗再現は AC#3 の協調アクティベーション端条件に依存。

### AC#2 複数ファイル同時
`urls` 配列を同期ループで順に処理し、各新規ウィンドウが makeKeyAndOrderFront を呼ぶため**配列の最後の URL のウィンドウが最終的に key/front**になる（後勝ち）。全ウィンドウは配列順に orderFront され最後が最前面。配列順は LaunchServices が渡す順(概ね引数順だが保証なし)。どのウィンドウをアクティブにするかの明示的ポリシーは無く、常に最後になる。

### AC#3 他アプリ active vs befold 自身 active
- befold が既に最前面: `NSApp.activate()` は実質 no-op、makeKeyAndOrderFront で確実に前面化 → 安定動作。
- 他アプリが最前面: macOS 14+ の引数なし `NSApp.activate()` は協調アクティベーション。open イベント処理には通常 activation 付与が伴い初回オープンは成功するが、**バックグラウンド常駐中に他アプリ最前面の状態で open イベントを受けると、システムがアクティベーションを遅延/拒否し Dock バウンスのみでフォーカスを奪えない可能性**がある。これが「アクティブにならない」最有力の再現条件。

### AC#4 原因の切り分け
- activate タイミング: 新規ブランチは showWindow の**前**に activate を呼ぶ。ただし両者とも同期で activate 後に makeKeyAndOrderFront が走るため順序自体はバグ要因ではない。
- 非同期ウィンドウ生成: 無し(レース要因なし)。
- 協調アクティベーション(macOS 14 の no-arg activate()): 他アプリからフォーカスを奪えない主因候補。
- Space またぎ: window.collectionBehavior は .fullScreenPrimary を insert するのみ(canJoinAllSpaces 等なし)。`rescueWindowsDetachedFromSpace` は**起動時のみ**で open 経路では呼ばれない。対象既存ウィンドウが別 Space にある場合、makeKeyAndOrderFront は Space 切替を強制するか可視フォーカスに失敗しうるが open 経路では未ケア。

### AC#5 対応方針
単一ファイル経路のロジックはおおむね妥当。実バグは (a) macOS 14 協調アクティベーションで他アプリ最前面時にフォーカスを奪えない点、(b) 複数ファイル時の後勝ち非明示ポリシー、の2点。
- 低リスク改善案: 前面化(makeKeyAndOrderFront/showWindow)の**後**に `NSApp.activate()` を呼ぶ順序に変更し、key ウィンドウ確定後にアプリを前面化する。
- 複数ファイル時にどのウィンドウを最終アクティブにするかのポリシー決定は複数ウィンドウ機能そのものである **TASK-73 側で扱うのが適切**。
- 単一ファイルの協調アクティベーション信頼性のみ、必要なら本タスク後の小さな独立修正として切り出し可。ただし手動再現で (a) の失敗が確認できるまでは緊急修正不要。

（本タスクは調査のみ。実装は方針合意後 or TASK-73 に委ねる想定でステータスは In Progress のまま）
<!-- SECTION:NOTES:END -->
