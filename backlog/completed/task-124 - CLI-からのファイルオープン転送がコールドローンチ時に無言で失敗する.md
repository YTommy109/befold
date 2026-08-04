---
id: TASK-124
title: CLI からのファイルオープン転送がコールドローンチ時に無言で失敗する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:21'
updated_date: '2026-07-25 01:19'
labels:
  - cli
  - bug
dependencies: []
priority: high
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で確認(CONFIRMED)。CLIInstanceRouter.forward()(CLIInstanceRouter.swift:73)は「ACK なしだが宛先プロセスが生存」を成功扱いにする。コールドローンチ時、AppDelegate が DistributedNotificationCenter の observer を登録する前に NSRunningApplication でアプリが検出され、リトライ総枠も maxForwardAttempts(3) × ackTimeout(0.5s) = 1.5s しかない(コードコメント自体がこの制約を認めている)。
遅いコールドスタート(アップデート直後の初回起動・遅いディスク)では 3 回の通知投稿がすべて observer 登録前に発火し、CLI は exit 0 するがファイルは開かず、エラーも表示されない。
関連: CLIInstanceRouter.swift:67 では post が waitForAck の observer 登録より先に実行されるため、post 直後〜登録前の窓とリトライ間の removeObserver の隙間で ACK を取りこぼす問題も同根。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 コールドローンチ時に `befold file.md` で確実にファイルが開く(observer 登録前の転送が失われない)
- [x] #2 転送が最終的に失敗した場合、CLI は非ゼロ exit とエラーメッセージを出す
- [x] #3 ACK 登録と post の順序に関する競合のテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化の検討: 症状は 3 つあるが、いずれも『ハンドシェイクが不確実なことを、リトライ・生存フォールバック・起動ポーリングの 3 つで部分的に補っている』構造から来ている。緩和策を足すのではなく、ハンドシェイクを正しくして補いを 1 つ減らす。
2. ACK 待ち受けを『観測の開始』と『待つ』に分離する AckWaiting を導入し、最初の post より前に 1 度だけ登録してリトライをまたいで保持する。
3. isDestinationAlive フォールバックを削除し、ACK 未観測は失敗として返す(ユーザー判断)。
4. maxForwardAttempts を 3 → 20 にし、総予算を CLIAppLauncher の pollTimeout と同じ 10 秒に揃える。
5. 順序競合のテスト(arm→post→wait の並び)と、実通知での取りこぼし検証を追加する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
原因: 3 つの症状(コールドローンチでの無言失敗・post/登録順の窓・リトライ間の removeObserver の隙間)は独立ではなく、ACK ハンドシェイクが不確実なことを 3 つの緩和策で補う構造に由来していた。緩和策を増やす代わりにハンドシェイク自体を正しくし、補いを 1 つ(生存フォールバック)減らす方針を採った。

実装:
- BefoldCLI/AckWaiting.swift を新設。protocol AckWaiting(wait/cancel)と、DistributedNotificationCenter 実装の DistributedAckWaiter。生成した時点で観測を開始するため、post より前に登録できる。観測フラグは投稿側スレッドからの配送に備えて NSLock で保護(旧 defaultWaitForAck のローカル var キャプチャは sendable-closure-captures の警告も出ていた)。
- forward(): waitForAck クロージャを makeAckWaiter シームへ置き換え、待ち受けをループの外側で 1 度だけ生成し defer で cancel。post → 登録の順序も、リトライ間の removeObserver の隙間も構造的に消えた。
- isDestinationAlive パラメータと生存フォールバックを削除。ACK 未観測は false を返す。呼び出し元 CLIAppLauncher.forwardOrReportFailure が既に stderr + exit 1 を持つため、無言失敗の経路がなくなった(AC#2)。再送は GUI 側が requestID で重複排除するため二重オープンにはならない。
- maxForwardAttempts を 3 → 20 に変更(× ackTimeout 0.5 秒 = 10 秒)。CLIAppLauncher がアプリの出現を待つ pollTimeout(10 秒)と同じ予算を『届いたことの確認』にも与える。旧コメントが認めていた 1.5 秒の制約を解消。

検証:
- 実装前に『ACK 未観測なら失敗を返す』テストを書き、旧実装が true を返して失敗することを確認(TDD の赤)。
- 順序競合のテスト(AC#3): ackWaiterIsArmedBeforeFirstPostAndKeptAcrossRetries が events == [arm, post, wait, post, wait, post, wait, cancel] を固定し、待ち受けの開始が最初の post より前・1 度だけ、解除が全再送後の 1 度だけであることを規定する。
- DistributedAckWaiterIntegrationTests(新規, 実 DistributedNotificationCenter): 待ち受け開始後・wait 呼び出し前に届いた ACK も観測されることを検証。旧実装では wait の中で登録していたためこの ACK を取りこぼしていた。3 回連続実行して安定(各 0.5 秒)。
- swift test: 612 tests / 85 suites pass。swiftformat --lint: 0/183 files require formatting。

AC#1 の検証範囲について: コールドローンチ実機での再現は GUI アプリの起動を伴うため本タスクでは行っていない。根拠は (a) 取りこぼしの窓が構造的に消えたことを実通知の統合テストで確認、(b) 総予算が 1.5 秒から 10 秒へ拡大、(c) 万一届かなかった場合は成功扱いされず必ず非ゼロ exit と stderr 出力になる、の 3 点。実機での最終確認はリリース前手動チェック(WebView/GUI 層と同じ扱い)に委ねる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI からの転送が無言で失敗する原因は、ACK ハンドシェイクの不確実さを 3 つの緩和策で補う構造にあった。AckWaiting を導入して『観測の開始』を post より前へ移し、リトライをまたいで登録を保持することで、post/登録順の窓とリトライ間の隙間を構造的に消した。そのうえで isDestinationAlive による成功フォールバックを削除し、ACK 未観測は失敗として非ゼロ exit + stderr 診断に落ちるようにした。再送予算も 1.5 秒から 10 秒(CLIAppLauncher の起動待ちと同じ)へ拡大。検証は TDD の赤を確認したうえで、順序を固定するユニットテストと実 DistributedNotificationCenter を使った取りこぼし検証を追加し、swift test 612 tests / 85 suites pass。コールドローンチ実機確認はリリース前手動チェックに委ねる旨を実装ノートに記録した。
<!-- SECTION:FINAL_SUMMARY:END -->
