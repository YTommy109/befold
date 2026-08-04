---
id: TASK-65
title: rename 伝搬を整理し現在ファイル URL の保持を一本化する
status: Done
assignee: []
created_date: '2026-07-19 02:57'
updated_date: '2026-07-19 04:45'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rename イベントが FileWatcher（befold/FileWatching/FileWatcher.swift:163-174）→ ViewerStore.handleRename（befold/Viewer/ViewerStore.swift:164-169）→ onFileRenamed → ViewerWindowController.handleRename（befold/App/ViewerWindowController.swift:262-291）→ delegate didRenameFrom → ViewerWindowManager.remapController（befold/App/ViewerWindowManager.swift:140-163）と 6 ホップ中継されている。加えて現在ファイル URL が ViewerStore.filePath / pendingURL と ViewerWindowController.fileURL（:53）で二重管理されている。controller 側の fileURL を store 由来に一本化し、applyURLToWindow（:358-363）と per-file 状態の migrate 3 連発（zoom / sourceMode / scroll、:269-271）を単純化する。per-file 状態ストア束の 1 オブジェクト化（PathKeyedDictionary は共通化済み）も検討する。2026-07-19 のアーキテクチャレビュー（データフロー観点）で特定。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 現在ファイル URL を保持する場所が 1 箇所になっている
- [x] #2 rename 時の per-file 状態（zoom / sourceMode / scroll）の移行が単一の呼び出しに集約されている
- [x] #3 既存の rename 系テスト（FileWatcher / ViewerStore / ViewerWindowController）が通過する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 単純化検討（着手前）
6ホップ中継の削減を最優先で検討した結果:
- FileWatcher(OSイベント源)→ViewerStore(監視+読込)→ViewerWindowController(ウィンドウ/UI)→ViewerWindowManager(controllers辞書) は各層の責務が明確に分離しており、ホップ統合は層のマージ=大規模化を招くため見送る。中継自体ではなく『URLの二重保持』と『migrate3連発』が実際の重複コスト。
- store側の pendingURL(即時ロード対象) と filePath(ロード完了後・observable) は統合不可: 統合すると『旧content+新filePath』の中間状態描画バグ(過去修正済み)が再発する。両者は非同期パイプラインの内部機構として不可分。
- よって二重管理の解消対象は controller.fileURL(:53) 対 store のURL。controller.fileURL を store 由来の computed に変更し、現在URLの可変保持先を store 一箇所へ集約する。

## 実装方針
1. PerFileStateStore を新設し ZoomStore/SourceModeStore/ScrollPositionStore を束ねる。単一 migrate(from:to:) を提供(AC2)。sub-store は public let で公開しテスト・getter/setterから利用。
2. ViewerWindowController/ViewerWindowManager/AppDelegate の3ストア注入を perFileState 1個に集約。ViewerContentView へは perFileState.zoom/.scrollPosition を渡し signature 据え置き。
3. handleRename の migrate 3連発 → perFileState.migrate(from:to:) の単一呼び出し(AC2)。
4. controller.fileURL を stored から computed(store.currentURL 由来)へ。store に currentURL を公開。init 中は fileURL パラメータを使用、外部読取は init 後(store.openFile 済)なので非nil。型の非Optional化のため bootstrap 定数でフォールバック(可変な現在URLの保持先は store 一箇所)(AC1)。
5. rename は store が old→new を握るため onFileRenamed を (old,new) の2引数へ変更。controller.handleRename(from:to:) が明示 old を受ける。applyURLToWindow から fileURL 代入を除去しタイトル/representedURL 更新のみへ単純化。
6. 全テスト(427)通過を安全網に、コンパイルエラー起点でテスト呼出側を機械的に追随修正。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装結果
- 新規 PerFileStateStore(befold/App/PerFileStateStore.swift): ZoomStore/SourceModeStore/ScrollPositionStore を束ね、単一 migrate(from:to:) を提供。ViewerWindowController/ViewerWindowManager/AppDelegate の3ストア注入を1オブジェクトへ集約。
- ViewerStore に currentURL(=pendingURL)を公開。現在ファイル URL の可変な保持先を store 一箇所へ集約。onFileRenamed を (oldURL,newURL) の2引数へ変更(旧 URL は store が握るため通知に含める)。
- ViewerWindowController.fileURL を stored→computed(store.currentURL 由来)へ。applyURLToWindow から fileURL 代入を除去(タイトル/representedURL 更新のみ)。handleRename(from:to:) は per-file 状態移行を perFileState.migrate の単一呼び出しへ集約。
- 型の非Optional化のため initialFileURL(不変ブートストラップ定数)でフォールバック。init 中は fileURL パラメータを使用し、外部読取は init 後(store.openFile 済)なので実際には到達しない。

## 単純化の反映
6ホップ中継は各層の責務分離が明確なため統合せず、実際の重複コスト(URL二重保持・migrate3連発)に絞って解消した(plan 参照)。

## 検証
- swift build: クリーン(警告なし)。
- swift test: 428 tests / 54 suites すべて通過。rename 系(FileWatcher detectsRename*, ViewerStore watcherRename*, ViewerWindowController rename* 3件)を含む。
- rename 単体テストは本番の呼出契約(store が現在URLを先に進めてから controller に通知)に合わせ、store.openFile で先行させる形へ更新。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
現在ファイル URL の保持を store.currentURL 一箇所へ集約し、ViewerWindowController.fileURL を computed 化。per-file 状態(zoom/sourceMode/scroll)を PerFileStateStore に束ね rename 移行を単一 migrate(from:to:) 呼び出しへ集約。swift build クリーン・swift test 428件全通過(rename 系含む)で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
