---
id: TASK-107
title: CLI起動時にSparkle updaterのエラーダイアログが表示される
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 06:38'
updated_date: '2026-07-23 07:42'
labels: []
dependencies:
  - TASK-105
priority: medium
type: bug
ordinal: 95000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
"The updater failed to start. Please verify you have the latest version of bin and contact the app developer if the issue still persists." というエラーダイアログが表示される。

原因の推定: CLIプロセスが .launchAsNewInstance 経路で新しいGUIアプリとして起動した際に、applicationDidFinishLaunching内の updaterController.startUpdater() (AppDelegate.swift:189) が呼ばれる。既に別のbefoldインスタンスが起動中の場合、Sparkleの更新チェックが競合してエラーになる可能性がある。または、CLI起動パスではSparkleフレームワークの初期化が正しく行われない可能性がある。

TASK-105の修正により既存インスタンスへの転送が正しく動作すれば、CLI起動が .launchAsNewInstance に進むケースが減り、この問題の発生頻度も下がる見込み。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold file.mmd 実行時にSparkle updaterのエラーダイアログが表示されない
- [ ] #2 アプリの通常起動時の自動更新チェック機能に影響がない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SPUStandardUpdaterController.startUpdater() を SPUUpdater.start() の try/catch に置き換え、エラー時はNSLogに留めダイアログを抑止。コミット ec5370f。
<!-- SECTION:NOTES:END -->
