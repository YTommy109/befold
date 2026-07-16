---
id: TASK-31.1
title: クリック無反応の実地切り分け用ログを追加する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-16 15:05'
updated_date: '2026-07-16 15:27'
labels: []
dependencies: []
parent_task_id: TASK-31
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-31の調査で、①MainActorが巨大ファイル読み込み処理により実質ブロックされている、②FileWatcherの再トリガーで古いloadTaskがキャンセルされず積み上がりCPUを圧迫している、という2つの仮説が浮上したが、いずれも実機での裏付けがない。修正に進む前に、実際に何が起きているか(クリックイベント自体が届いていないのか、届いているが処理が追いついていないのか)をログで切り分ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーのTapGesture発火・openFile呼び出し・loadContent開始・古いloadTaskの残存状況・performLoad完了(apply適用)のタイミングが時刻付きログで追跡できる
- [x] #2 巨大SJIS CSV表示中に軽量ファイルへ切り替えて反応が遅れる事象を実機で再現し、ログから「クリック自体が認識されていない」のか「認識されているが表示反映が遅延している」のかが判別できている
- [x] #3 ログの結果に基づき、根本原因(MainActorブロック/タスク未キャンセルによるCPU競合/その他)が一つに絞り込まれている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. os.Logger(subsystem: "com.degino.befold", category: 各ファイル対応)を新規導入する
2. 計装ポイントを追加する:
   - FileListView.singleTapGesture: タップ認識ログ(entry名, 時刻)
   - ViewerWindowController.switchFile/performFileSwitch: 切替要求ログ
   - ViewerStore.openFile/loadContent: 読み込み要求ログ(generation番号)
   - ViewerStore.performLoad: computeLoad呼び出し前後でThread.isMainThreadを記録
   - FileWatcher.scheduleNotify/onChange: 再トリガー発生ログ(パス, サイズ/mtime)
3. MainActorブロック仮説を直接検証するため、100ms間隔でMainActor上にハートビートログを出す診断用プローブを一時的に追加する(DEBUGビルドのみ)
4. ビルドし、巨大SJIS CSV表示中に軽量ファイルへ切り替える操作を手動再現し、log stream --predicate 'subsystem == "com.degino.befold"' でログを収集する
5. ログを分析し、根本原因(MainActorブロック/タスク未キャンセルによるCPU競合/クリック自体の未認識/その他)を一つに絞り込む
6. 結論をtask-31.1に記録し、診断用ログ・プローブは元に戻す(恒久化はしない)
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
os.Logger(subsystem: com.degino.befold)による一時計装とMainActorハートビートプローブ(100ms間隔)を追加し、24MBのSJIS CSVで実機再現した。

【判明した事実】
- MainActorハートビートは終始一切乱れなし → MainActorが直接ブロックされている、という仮説は否定された
- computeLoad(nonisolated static func)は設計通りバックグラウンドスレッドへ正しくホップしていた(mainThread=false を確認)
- readData自体は数msで完了(I/Oは問題なし)
- しかし NormalizedTextCache(data:) の完了までに、23MBファイルで約36秒、25MBファイルで約52〜59秒かかっていた(異常な遅さ)
- FileWatcherが表示中に再トリガーし、loadContentが古いloadTaskを一度もキャンセルしないまま新タスクを積み増していることも確認(previousTaskStillSet=trueで検出)。ただし今回の実測では2並列タスクがCPUコアを枯渇させるほどではなく、この積み増し自体は副次的要因

【根本原因】
BefoldApp/BefoldKit/TextEncoding.swift:53-57 の detectEncoding() で、NSString.stringEncoding(for:) をファイル全体(data)に対して呼んでいる。
sniffLength(8192バイト、コメントで『バイナリ判定・エンコーディング判定に見る先頭バイト数』と明記)は detectBOM や looksLittleEndianUTF16 では使われているのに、この最重量処理(ICUベースのエンコーディング推定)だけ適用されておらず、ファイル全体を舐めている。これが数十秒の処理時間の直接原因。

読み込み中に再度クリックしても反応が遅れて見えるのは、MainActorブロックではなく、この長時間タスクが完了するまで表示が更新されない(かつFileWatcher再トリガー時は重複タスクが積み増される)ため。

診断用ログ・ハートビートプローブは全てgit checkoutで元に戻し、恒久化していない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
os.Loggerによる一時計装(タップ〜openFile〜loadContent〜performLoad/computeLoadの各段階のログ、MainActor 100msハートビートプローブ)を追加し、24MB SJIS CSVで実機再現して検証した。ハートビートに乱れがなくMainActorは終始ブロックされていないことを確認。一方、TextEncoding.detectEncoding内のNSString.stringEncoding(for:)呼び出しがsniffLength(8192バイト)を適用せずファイル全体を対象にしており、23〜25MBのSJIS CSVでNormalizedTextCache生成に36〜59秒かかっていることを直接測定した。クリック無反応に見える症状は、クリックの取りこぼしではなくこの長時間処理の完了待ちであることが判明。診断用コードはgit checkoutで全て復元し、恒久化していない。
<!-- SECTION:FINAL_SUMMARY:END -->
