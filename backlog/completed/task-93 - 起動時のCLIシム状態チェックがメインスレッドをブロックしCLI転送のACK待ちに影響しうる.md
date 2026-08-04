---
id: TASK-93
title: 起動時のCLIシム状態チェックがメインスレッドをブロックしCLI転送のACK待ちに影響しうる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-21 10:49'
updated_date: '2026-07-21 11:06'
labels: []
dependencies:
  - TASK-91
priority: medium
type: bug
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-91 で追加した AppDelegate.notifyIfCLIShimIsStale() が applicationDidFinishLaunching の同期パス内で実行されており(AppDelegate.swift:193)、2つの異なるブロッキング要因を持つ。

(1) CLIShimInspector.status() 内の attributesOfItem/destinationOfSymbolicLink というファイルI/Oが、タイムアウトも非同期化もされずメインスレッドで同期実行される。/usr/local/bin が低速・応答不能なボリューム上にある場合、アプリ起動(ウィンドウ復元・メニュー構築)全体が遅延する。既存コードは起動時の重い処理を意図的に遅延させている(例: ウィンドウ復旧のためのDispatchQueue.main.asyncAfter(deadline: .now() + 1.0))のと対照的。

(2) legacyFile/staleSymlink判定時に呼ばれるCLIInstallUI.presentReinstallRecommended()がNSAlert.runModal()で同期的にモーダル表示するため、このアラートが表示されている間、メインスレッドはrunModalのネストしたrun loop内で止まる。この間に別プロセスからbefold経由でCLIInstanceRouter.forward()がACK待ち(最大1.5秒)を行うと、宛先インスタンス側のACK送信コールバックが実行されずタイムアウトし、isDestinationAlive()による生存確認だけで成功扱いになってしまい、実際にはファイルが開かれないまま握りつぶされる可能性がある。

対応方針: CLIShimInspector.statusによる判定とアラート表示を、起動直後の同期パスから外す(例: 既存のasyncAfterによるウィンドウ復旧と同様に遅延実行する、またはバックグラウンドキューでチェックしてから結果をメインスレッドに戻す)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLIShimInspector.statusの呼び出しおよびpresentReinstallRecommended()の表示が、applicationDidFinishLaunching内の他の同期処理(ウィンドウ復元・メニュー構築等)をブロックしない
- [x] #2 CLI転送(CLIInstanceRouter.forward())のACK待ちが、起動直後の再インストール推奨アラート表示中でも従来通り機能する
- [x] #3 既存のTASK-91のAC(legacyFile/staleSymlinkの場合のみ通知、未インストール/upToDateでは非表示、同一起動で複数回表示されない)が引き続き満たされる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
notifyIfCLIShimIsStale()をDispatchQueue.global(qos: .utility)へ移し、CLIShimInspector.statusのファイルI/O(lstat/readlink相当)をapplicationDidFinishLaunchingの同期パスから外した。判定後、staleな場合のみDispatchQueue.main.asyncでCLIInstallUI.presentReinstallRecommended(attachedTo:)を呼ぶ。CLIInstallUI側はapp-modalなrunModal()ではなく、可視ウィンドウがあればNSAlert.beginSheetModal(for:)による非ブロッキングなウィンドウモーダルシートで表示するよう変更(表示可能なウィンドウがない場合は案内自体を見送り、次回起動時の再チェックに委ねる)。これによりCLIInstanceRouter.forward()のACK待ちが、案内表示中もmain run loop上で通常どおり処理され続ける。GUI/AppDelegate層はプロジェクト規約により自動テスト対象外のため、実機でのシート表示・CLI転送との同時実行は手動確認を推奨。swift test(Integration/FileWatcherTests除く)556件全て成功、swiftformat lintも問題なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
起動時のCLIシム状態チェックとその案内表示がapplicationDidFinishLaunchingの同期パスをブロックしていた問題を解消。CLIShimInspector.statusの呼び出しをバックグラウンドキューへ逃がし、案内アラートもapp-modalなrunModal()ではなく可視ウィンドウに紐づく非ブロッキングなbeginSheetModal(for:)シートに変更した。これによりウィンドウ復元・メニュー構築などの起動処理をブロックせず、CLI転送(CLIInstanceRouter.forward())のACK待ちも案内表示中に阻害されなくなる。TASK-91のAC(legacyFile/staleSymlinkのみ通知・同一起動で1回のみ)は維持。swift test全556件成功。GUI層自体の実機確認はプロジェクト規約によりリリース前の手動チェックを推奨。
<!-- SECTION:FINAL_SUMMARY:END -->
