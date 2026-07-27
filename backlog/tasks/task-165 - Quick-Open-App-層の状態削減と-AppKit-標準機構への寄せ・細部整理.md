---
id: TASK-165
title: Quick Open App 層の状態削減と AppKit 標準機構への寄せ・細部整理
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-27 05:49'
updated_date: '2026-07-27 07:35'
labels: []
dependencies: []
priority: low
type: task
ordinal: 240000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
レビューで見つかった App 層の小規模な設計改善をまとめて行う。個々は軽微だが、いずれも状態や二重表現を減らしバグの入り込む余地を狭める。

(1) AppDelegate.quickOpenOriginController（weak var 状態）の削除: NSPanel は canBecomeMain が false のため、パネルがキーの間も NSApp.mainWindow は元のビューアウィンドウのまま。weak 状態を持たず NSApp.mainWindow?.windowController as? ViewerWindowController を都度引けば、「パネル表示中に元ウィンドウが閉じられた」ケースでも残存ウィンドウへ自然に切り替わる（現状は nil フォールバックで新規ウィンドウを開いてしまう）。

(2) NSApp.keyWindow?.windowController as? ViewerWindowController パターンが AppDelegate 内に3箇所（applicationShouldTerminate / showOpenPanel / makeQuickOpenEnvironment）。computed property に共通化する（(1) 採用時は mainWindow 版）。

(3) QuickOpenPanelController.hidesOnDeactivate = true は冗長: アプリ非アクティブ時は windowDidResignKey → dismiss() が先に走るため一度も仕事をしない。削除して「閉じる契機は resignKey」に意図を一本化する。

(4) dismiss() の orderOut + 参照破棄を close() に変える: isReleasedWhenClosed = false なので close() は安全で、AppKit のウィンドウ終了経路（windowWillClose 通知、ウィンドウリスト登録解除）に乗る。

(5) QuickOpenModel.queryText の storedQueryText + 明示 setter を didSet に戻し、QuickOpenView の手組み Binding(get:set:) を @Bindable + $model.queryText に置き換える: @Observable マクロは格納プロパティの willSet/didSet を保持する（ドキュメント化された挙動）。現在のコメントは TASK-159 実装時の切り分け不足（実際の原因は sizingOptions 欠落だった）に基づくもので、根拠が成り立たない。

(6) ViewerWindowManager.sharedGitFileIndex: private let gitFileIndex の別名 computed property で、同じものに2つの名前と2つの /// がある。let を internal にして1つに畳む。

(7) MainMenuBuilder の Print keyEquivalent が大文字 "P" + マスクで、同ファイルの shift 併用項目（redo/findPrevious/hideOthers）の小文字 + マスク方式と不揃い。"p" に揃える（表示・挙動は不変）。

(8) 上限値 20/50 の二重定義: QuickOpenModel.fuzzyLimit/historyLimit と Kit 側 initialCandidates(limit: = 20)/matches(limit: = 50) のデフォルト値が同じ知識の二重表現。モデルは常に明示指定するので Kit 側のデフォルト引数を外す。

(9) ドキュメント系: SuffixPathIndex.allCandidates の /// に O(n log n) である旨と「構成要素を持たない候補は一覧にも現れない」旨を追記。QuickOpenCandidates.originBonus の「一致の質を覆すほどではない」コメントは recent+30 > consecutive+boundary=27 で厳密には偽なので文言修正か定数間の不等式をテストで固定。DirectoryFileScanner の contentsOfDirectory 失敗（権限なし等）の黙殺は「黙って切り捨てない」という設計意図と食い違うため、判断コメントを書くか失敗時も truncated 扱いを検討。

(10) リリース前手動チェック項目に「タイプして候補が増減したときのパネルの動き（上端固定か）」を追加: preferredContentSize 追従の高さ変化は NSWindow 既定では原点（左下）基準のため、上端が動いて見える可能性がある。動くようなら高さ変化分の setFrameOrigin 補正を入れる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 quickOpenOriginController が削除され、切り替え先の解決が NSApp.mainWindow 経由になる（パネル表示中に元ウィンドウを閉じても残存ウィンドウへ切り替わることをテストまたは手動確認で検証）
- [x] #2 keyWindow/mainWindow → ViewerWindowController の変換が1箇所に共通化される
- [x] #3 hidesOnDeactivate の削除・close() への変更後も、Esc/フォーカス喪失/再オープンの動作が手動確認で維持されている
- [x] #4 queryText が didSet + @Bindable の標準形になり QuickOpenModelTests が通る
- [x] #5 上限値のデフォルト引数二重定義と sharedGitFileIndex の別名が解消される
- [x] #6 ドキュメント系(9)と手動チェック項目(10)が反映される
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
コード変更完了・swift test 全736パス・lint クリーン(commit 5d4f1383)。検証済み: AC#2(activeViewerController computed property に3箇所集約)/AC#4(queryText を didSet に戻し QuickOpenView を @Bindable+$、QuickOpenModelTests パス)/AC#5(initialCandidates/matches の既定 limit 撤去・sharedGitFileIndex 別名を internal gitFileIndex に一本化)/AC#6(allCandidates の O(n log n)・構成要素なし除外、originBonus コメント修正、DirectoryFileScanner の存在するのに不可読を truncated 扱い、手動チェック項目(10)追加)。未検証: AC#1(元ウィンドウを閉じても残存ウィンドウへ切替)と AC#3(Esc/フォーカス喪失/再オープンで close() 後も動作維持)は GUI 手動確認が必要でエージェント環境では実行不可。ユーザー確認待ち。

GUI 手動確認(System Events, debug ビルドを起動)で AC#1/#3 を検証:
- AC#3: Cmd+P でパネル出現(1→2窓)、Esc で閉(2→1)、再 Cmd+P で再出現(1→2, close() 後も再オープン可)、Finder を前面にしてフォーカス喪失させるとパネルのみ閉じメインウィンドウは残存(再アクティブ化で 1 窓=alpha.md)。
- AC#1: alpha/beta の 2 窓で alpha を前面にし Cmd+P(3窓)→パネル表示中に alpha を閉じ(2窓=beta+パネル)→'gamma' 入力して Enter→結果 1 窓=gamma.md。旧実装なら閉じた origin が nil で新規ウィンドウ(2窓)になるはずが、残存 beta ウィンドウが gamma.md へ切り替わった=mainWindow 経由の解決が意図どおり機能。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
レビュー指摘10項目を是正: quickOpenOriginController(weak状態)を mainWindow ベースの activeViewerController に一本化(keyWindow→VWC 3箇所を集約)、hidesOnDeactivate 削除・dismiss を close() 化、queryText を didSet+@Bindable に、sharedGitFileIndex 別名を internal gitFileIndex に、Print キーを小文字統一、initialCandidates/matches の既定 limit 撤去、ドキュメント整備(allCandidates O(n log n)/originBonus/走査失敗の truncated 化)と手動チェック項目追加。swift test 全736パス+lint クリーン、AC#1/#3 は起動して System Events で GUI 手動確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
