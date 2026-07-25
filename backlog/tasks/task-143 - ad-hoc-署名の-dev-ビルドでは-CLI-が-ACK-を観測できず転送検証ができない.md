---
id: TASK-143
title: ad-hoc 署名の dev ビルドでは CLI が ACK を観測できず転送検証ができない
status: Done
assignee:
  - '@claude'
created_date: '2026-07-25 06:50'
updated_date: '2026-07-25 07:48'
labels:
  - cli
  - build
  - test
dependencies: []
priority: medium
ordinal: 219000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
xcodebuild で作った Debug ビルド(.build/xcode/.../befold.app)の同梱 befold-cli から起動中インスタンスへ転送すると、要求は GUI に届き GUI は 2-13ms で ACK を post しているのに、CLI プロセス側の DistributedAckWaiter が ACK を一度も観測できず 10 秒(20 回再送)を使い切って exit 1 + 'Failed to forward to the running instance.' になる。ファイル自体は開くため、転送の実挙動を CLI の終了コードで検証できない。

切り分け結果(2026-07-25):
- リリース版(/Applications/befold.app 1.7.3-dev.19)の同梱 CLI → 同じ手順で exit 0(成功)。
- リリース版 GUI + dev ビルド CLI → 失敗。dev GUI + dev CLI → 失敗。よって受信側ではなく送信側(dev ビルドの CLI バイナリ)が ACK を受け取れていない。
- 署名の差: リリース版 CLI は TeamIdentifier=X3587J4U72、entitlement は X3587J4U72.com.degino.befold-cli。dev ビルド CLI は Signature=adhoc / TeamIdentifier=not set で application-identifier に team プレフィックスがない(+ get-task-allow)。team プレフィックスなしの application-identifier を持つプロセスが Distributed Notification を受信できていない可能性が高い。
- 変更前のコード(TASK-134 の stash 前)でも同一症状のため、特定の変更による回帰ではない。

影響は開発時の検証手段のみ(製品の不具合ではない)。CLI 転送を触るタスクの受け入れ確認が終了コードで取れず、通知リスナを別途用意する必要がある。

対応案: (a) 原因を entitlement/署名まで特定し、dev ビルドでも受信できる署名設定にする(ローカル署名 ID の利用や application-identifier の付与見直し)。(b) 直せない場合は、検証手順として『Distributed Notification リスナで request/ack を観測する』方法を docs に残し、終了コードに依存しないことを明記する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 dev ビルド(ad-hoc 署名)の befold-cli から起動中インスタンスへ転送したとき、exit 0 で成功する。または終了コードで検証できない理由と代替の検証手順が docs に残っている
- [x] #2 ACK を観測できない原因(署名/entitlement のどの差か)が特定され、タスクに記録されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査(2026-07-25, 実測): 当初の仮説『ad-hoc 署名/entitlement が原因で Distributed Notification を受信できない』は誤りだった。

計測1: 最小プローブ(swiftc でビルドした observer/poster)を ad-hoc 署名 / Developer ID 署名 / dev ビルドと同じ entitlements(team プレフィックスなし application-identifier + get-task-allow)の全組合せで実行。4 通り全てで userInfo 付きで配送成功。署名は配送を止めていない。

計測2: dev CLI が転送に失敗している最中に、別プロセスの ad-hoc 署名オブザーバは GUI の ACK を受信できていた(requestID も一致)。つまり ACK は正しく配送されている。

計測3: dev CLI に一時計測を入れると、オブザーバ登録・wait ともに main スレッド・同一 runloop で実行されているのに、ブロックが一度も発火しない。外部プロセスから ACK を投げても発火しない(GUI 側の問題ではない)。

計測4(決定的): CLI プロセスの入口(ArgumentParser の async main に入る前、同期コンテキスト)で同じオブザーバを登録して runloop を回すと ACK を受信できる。一方 run() 内(async コンテキスト)では受信できない。さらに async コンテキスト内で『runloop を回す』代わりに『await Task.sleep する』と受信できる。

根本原因: DistributedAckWaiter.wait が RunLoop.current.run(mode:before:) を Swift 並行処理の async コンテキスト(ArgumentParser の AsyncParsableCommand → @MainActor run() async)から同期的に回している。この経路では通知が配送されない(コンパイラも RunLoop.run(_:before:) を『async コンテキストでは使用不可』としている。同期関数に包んでいるため警告が出ていなかった)。

リリース版 CLI が exit 0 だった理由: v1.7.3-dev.19 時点の CLIInstanceRouter.forward には『全試行で ACK 未観測でも宛先プロセスが生存していれば成功扱い』のフォールバックがあり(3 回 × 0.5 秒で打ち切り)、ACK を観測できていたわけではない。実測でもリリース版 CLI の成功は約 1 秒 = 打ち切り + 生存フォールバックのタイミングと一致する。HEAD はこのフォールバックを意図的に廃止したため、ACK 未受信がそのまま exit 1 として表面化した。

影響範囲の訂正: これは dev ビルド固有ではなく、HEAD のコードでは署名に関わらず CLI からの転送が常に ACK 未観測 → exit 1 + stderr メッセージになる(ファイル自体は開く)。テストが緑なのは、テスト関数が同期でありプロダクションと違う実行コンテキストから wait を呼んでいるため。

修正: ACK 待ちを runloop 回しから async 待機へ変更した。
- AckWaiting.wait を async 化し、DistributedAckWaiter は RunLoop.current.run(mode:before:) の代わりに Task.sleep(20ms) でポーリングする(await による中断点があれば通知はメインキュー側で配送される)。
- 波及: CLIRequestForwarder.forward / forwardBookmark / postAwaitingAck、CLIAppLauncher.run / launch、CLIBookmarkRouter.add、CLIBookmarkCommand.run、BefoldCLICommand の呼び出しを async 化。ついでに CLIAppLauncher のアプリ起動待ちも Thread.sleep から Task.sleep に変え、待機中にメインアクターを塞がないようにした。
- テスト: StubAckWaiter と CLI 系テストを async 化(646 tests パス)。

検証(実測):
- SPM ビルド(ad-hoc)CLI → 起動中インスタンスへ転送: 修正前 exit 1 / 10 秒、修正後 exit 0 / 83ms。
- xcodebuild Debug ビルド(ad-hoc 署名、TeamIdentifier=not set)の同梱 CLI → exit 0 / 329ms。AC#1 の『dev ビルドの CLI から転送して exit 0』を満たす。
- swift test 全体 646 tests / 93 suites パス。

AC#2 の回答(当初の想定と異なる): 原因は署名でも entitlement でもない。ad-hoc / Developer ID / dev 相当 entitlement の全組合せで配送は成立する。真因は『ACK 待ちが Swift 並行処理の async コンテキストから RunLoop を同期的に回していたこと』。

未検証(手動確認が必要な範囲): 起動中インスタンスが無い場合のアプリ新規起動→転送経路と --bookmark の転送経路は、実機 e2e ではなくユニットテストのみで確認している(前者は稼働中の GUI を終了させる必要があり、後者は利用者の実ブックマークデータを書き換えるため)。

補足(影響範囲の訂正): この不具合は dev ビルド固有ではなく HEAD のコード全体に及ぶ。リリース版が成功して見えたのは v1.7.3-dev.19 時点の『宛先プロセスが生存していれば成功扱い』フォールバックによるもので、HEAD ではそれを廃止済みのため、署名に関わらず CLI 転送が常に exit 1 + stderr メッセージになっていた(ファイル自体は開く)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI の ACK 待ちが Swift 並行処理の async コンテキストから RunLoop を同期的に回していたため Distributed Notification が配送されず、転送が常に失敗扱いになっていた。AckWaiting.wait を async 化し Task.sleep ポーリングへ変更(関連する forward / launcher / bookmark 経路も async 化)。dev ビルド(ad-hoc 署名)同梱 CLI で exit 0 / 329ms、SPM ビルドで exit 0 / 83ms、swift test 646 tests パスで確認。当初の署名/entitlement 仮説は署名の全組合せでの配送実測により否定した。
<!-- SECTION:FINAL_SUMMARY:END -->
