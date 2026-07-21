---
id: TASK-81
title: CLIInstanceRouter が ACK 消失を配送失敗と区別できず、false failure・activate 未実行・二重起動が起きる
status: Done
assignee: []
created_date: '2026-07-21 05:45'
updated_date: '2026-07-21 06:05'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/CLIInstanceRouter.swift
  - BefoldApp/befold/App/AppDelegate.swift
priority: high
type: bug
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIInstanceRouter.forward() は宛先からの ACK 通知を受信できた場合のみ成功と判定する。ACK は DistributedNotificationCenter 経由で、request 側同様に配送不安定（task-73.6 が対処したのと同じクラスの問題）だが、reply 側の ACK 消失は一切考慮されていない。
結果として、既存インスタンスが実際にはリクエストを正しく処理していても forward() は false を返し:
- パスありの CLI 起動: decideLaunchAction が .exitWithForwardError となり、ファイルは開けているのに CLI プロセスが「既存インスタンスへの転送に失敗しました」と表示して exit 1 する（false failure）。
- 旧コードで無条件に呼ばれていた instance.activate() が ACK 成功ブランチの中に移動したため、ACK が失われるとファイルは開いても既存インスタンスが前面化しない。
- パスなしの CLI 起動: decideLaunchAction が .launchAsNewInstance となり、ACK 消失時に新規 GUI インスタンスが起動して二重起動する（task-73.7 で解消したはずの症状が別経路で再発）。
根本原因は、forward() が『宛先未到達』と『宛先は処理したが ACK だけ消失』を区別できない設計にあること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ACK が失われても宛先インスタンスがリクエストを実際に処理していた場合に、CLI プロセスが誤って失敗（非ゼロ終了・エラーメッセージ）を報告しない
- [x] #2 ACK 消失時でも、宛先インスタンスが生存し処理済みであれば activate() 相当の前面化が行われる
- [x] #3 パスなし CLI 起動で ACK が失われても、宛先インスタンスが生存していれば新規 GUI インスタンスを二重起動しない
- [x] #4 上記シナリオ（ACK 消失かつ宛先は正常処理）を再現するテストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. forward() に isDestinationAlive/activate をDI可能なclosureとして追加。ACK待ちをmaxAttempts回試してもACKが得られない場合、宛先プロセス(NSRunningApplication)がまだ生存していれば「ACK消失だが処理済み」とみなしtrueを返しactivate()する。宛先が実際に終了している場合のみ真の配送失敗としてfalseを返す。\n2. 新しい状態やプロトコルは追加せず、既存のNSRunningApplication.isTerminatedという既存シグナルを転用する単純化方針を採用(ACK消失検知用の新規プロトコルは追加しない)。\n3. activate()呼び出しをACK成功ブランチだけでなく生存フォールバック分岐でも行うことでAC#2(前面化)を満たす。\n4. decideLaunchAction/AppDelegate側は変更不要(forward()の戻り値が変わるだけで既存分岐がそのままAC#1,#3を満たす)。\n5. CLIInstanceRouterTestsに新規テストケースを2件追加(生存時true・終了時false)、既存テストにactivate呼び出し検証を追加。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化検討: ACK消失/未到達を区別する新しいプロトコルや状態を追加する代わりに、既に取得済みのNSRunningApplication(既存インスタンス)のisTerminatedを転用して『生存していればACK消失とみなし成功扱い』とする方針を採用。DIされたactivate()をACK成功時だけでなく生存フォールバック時にも呼ぶよう修正。CLIInstanceRouterTests: 5テスト全て green。AppDelegate/decideLaunchActionは変更不要（forward()の戻り値のみで既存ロジックがAC#1,#3を満たす）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLIInstanceRouter.forward() に isDestinationAlive/activate をDI可能なclosureとして追加。maxAttempts回ACK待ちしても届かない場合、宛先NSRunningApplicationが生存していれば(!isTerminated)ACK消失とみなしtrueを返しactivate()する。宛先が実際に終了していた場合のみfalseを返す(真の配送失敗)。新しい状態やプロトコルは追加せず既存のisTerminatedシグナルを転用する単純化方針を採用。AppDelegate/decideLaunchActionは無変更でforward()戻り値のみでfalse failure/未activate/二重起動の全てが解消される。検証: CLIInstanceRouterTestsに新規2ケース(ACK消失+生存→true+activate/ACK消失+終了→false)を追加し既存3ケースと合わせ5件green。プロジェクト全543テストgreen。
<!-- SECTION:FINAL_SUMMARY:END -->
