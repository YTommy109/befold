---
id: TASK-257
title: DistributedAckWaiter に通知センターの注入シームを設け否定検証を unit 化する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-01 23:40'
updated_date: '2026-08-02 00:33'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 450060
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-249 で否定検証(別 requestID の ACK を観測しない / cancel 後は観測しない)を番兵方式にしたが、実配送(DistributedNotificationCenter)を使う限り以下の制約が残る。
- 同一 post 内の observer 呼び出し順が規定されないため、番兵 1 段では偽陰性の窓が残る(対象がまだ呼ばれていないだけを、観測しなかったと誤判定しうる)
- 窓を閉じる 2 段番兵は実測でフル実行 6 回中 4 回失敗(単独実行では 10/10 グリーン)。配送がメインランループ経由のため、他スイートがメインアクターを長時間占有していると配送自体が数秒単位で止まり、待機を増やすほど予算超過しやすくなる
根本解決として、DistributedAckWaiter に NotificationCenter の注入シームを設ける。DistributedNotificationCenter は NotificationCenter のサブクラスなので、AckWaiting.swift の init に `center: NotificationCenter = DistributedNotificationCenter.default()` を 1 つ足すだけで済む(addObserver(forName:object:queue:using:) / removeObserver はそのまま使える)。
これで否定検証はローカルの NotificationCenter に対して行える。ローカルの post は戻る前に全 observer を同期的に呼び切るため、(1) observer 呼び出し順の窓が構造的に消える(番兵自体が不要) (2) IPC もランループも介さないので飢餓の影響を受けず負荷時に赤くならない (3) 実行時間ゼロ相当、wait(timeout: 0) への暗黙依存も不要になる。
Integration 側には「実 DistributedNotificationCenter を通した往復が成立する」肯定テスト(ackArrivingBeforeWaitIsStillObserved)だけを残す。否定 2 本が検証しているのは requestID フィルタと cancel() による解除という waiter 自身のロジックであって IPC の挙動ではないため、テスト規約の「注入シームがあるなら unit 化し、Integration に残すのは実挙動が本質のものだけ」に合致する。
トレードオフ: テストのためにプロダクトへ引数を 1 つ足す。既に directoryLister / watcherFactory 等で同じ判断をしており一貫性はある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DistributedAckWaiter が NotificationCenter を注入でき、既定値は現行と同じで本番挙動が変わらない
- [x] #2 否定検証 2 本がローカル NotificationCenter に対する unit テストになり、番兵が不要になる
- [x] #3 Integration には実配送の往復を確かめる肯定テストのみが残る
- [x] #4 フル swift test を 5 回連続で実行しグリーンであることを確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AckWaiting.swift: DistributedAckWaiter.init に center: NotificationCenter = DistributedNotificationCenter.default() を追加、addObserver/removeObserver で使用。プロトコル doc に「timeout:0 は即時観測状態を返す」旨は既存のまま維持。
2. CLIRequestWire.swift: sendAck(requestID:center:) に center: NotificationCenter = DistributedNotificationCenter.default() を追加。center が DistributedNotificationCenter の場合のみ postNotificationName(...deliverImmediately:true) を使い(本番挙動を厳密に維持)、それ以外(注入されたローカル NotificationCenter)は標準の post(name:object:userInfo:) を使う。
3. 新規ファイル BefoldApp/befoldCLITests/AckWaitingTests.swift (unit) を追加し、否定検証2本(別requestIDのACKは観測しない/cancel後は観測しない)をローカル NotificationCenter() 注入で移設。番兵・wait(timeout:0)への暗黙依存を解消し、post が同期的に届く前提でロジックのみを検証する。
4. DistributedAckWaiterIntegrationTests.swift から否定検証2本を削除し、実配送の往復を確認する肯定テスト(ackArrivingBeforeWaitIsStillObserved)のみを残す。飢餓の実測知見を要約したコメントは残しつつ、番兵に関する記述を除去。
5. swiftformat / swift build / 対象テスト単体実行 / swift test 全体を5回連続実行してグリーンを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
center 注入シームを AckWaiting.swift / CLIRequestWire.swift に追加。否定検証2本を AckWaitingTests.swift(unit)へ移設、Integration には肯定テストのみ残した。フル swift test を5回連続実行しグリーン(951 tests, 142 suites)。対象単体は10回連続グリーン・実行時間0.001秒。コミット da40952。

修正ラウンド1: レビュー指摘対応。sendAck の center 型判定分岐を除去し、CLIRequestWire.ackUserInfo(requestID:) というワイヤ表現の公開に置き換え(プロダクトから実行時型判定が消えた)。DistributedAckWaiter.cancel() を self.center.removeObserver に修正(保持している center を無視していたバグ)。記録の訂正: 'wait(timeout: 0) への暗黙依存が不要になった' は不正確で、正しくは依存の性質が変わった(即時に返ることが正しさの前提ではなく、post が同期配送のため即座に正しい値が読めるようになった)。フル swift test を pipefail 付きで3回連続実行しグリーン(951 tests, 142 suites)。コミット 2817373。

レビュー指摘の反映(2817373):
- Important-1: 初版は sendAck にも center 引数を足し `center as? DistributedNotificationCenter` で分岐していた(postNotificationName(...deliverImmediately:) が plain NotificationCenter に無いため)。動作は正しかったが、引数の静的型が NotificationCenter なのに動的型で post の意味(コアレッシング回避の有無)が変わる形で、規約の DI 方針(振る舞いの注入)からも外れていた。レビューの代替案どおり、テストが必要としているのは post の実装ではなくワイヤ表現であると整理し、ackUserInfo(requestID:) を公開して sendAck を引数なしの元の形へ戻した。リポジトリ全体で `as? DistributedNotificationCenter` は 0 件になり、キーの組み立ては ackUserInfo 1 箇所・読み出しは ackRequestID(from:) という対称形が保たれている
- Important-2: cancel() が self.center ではなく DistributedNotificationCenter.default() に removeObserver していた。レビューの実測でクロスセンター解除は実際に効くと確認されたが未文書化の挙動依存であり、保持している center を無視する形は読み手に誤解を与えるため center.removeObserver へ修正
- スイートの /// に「sendAck にはシームを設けていない(本番の deliverImmediately: true を型判定なしに保つため)」と設計意図を記録し、将来また sendAck にシームを足そうとする人への歯止めにした
検証強度(レビューによる評価): ローカル NotificationCenter の post は戻る前に全 observer を同期的に呼び切るため、TASK-249 で問題にした「対象 observer がまだ呼ばれていないだけ」の窓が構造的に消えた。追加した正常系 ackForMatchingRequestIDIsObserved が番兵の役割を構造的に代替しており(これが無いとローカル center が実は何も配送していない場合に否定 2 本が空振りで通る)、全体として検証強度は向上している。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DistributedAckWaiter に NotificationCenter の注入シームを設け、否定検証 2 本をローカル NotificationCenter に対する unit テストへ落とした。ローカルの post は戻る前に全 observer を同期的に呼び切るため、TASK-249 で問題になった「observer 呼び出し順が保証されず、対象がまだ呼ばれていないだけの状態を観測しなかったと誤判定する」窓が構造的に消えた。番兵も wait(timeout: 0) の即時返却への依存も不要になり、実行時間は 1.0 秒 → 0.001 秒。
Integration には実配送の往復を確かめる肯定テストのみを残し、この 1 本が本番経路(deliverImmediately: true)を実際に通過することで「本番でしか通らない分岐」を防いでいる。
初版では sendAck にも注入シームを足して型判定で分岐していたが、レビュー指摘により「テストが必要としているのは post の実装ではなくワイヤ表現」と整理し、ackUserInfo(requestID:) の公開に置き換えてプロダクトから実行時型判定を除去した。
検証: 対象スイート 10 回連続、フル swift test 3 回連続(set -o pipefail で EXIT=0 確認)、レビュー担当も 951 tests グリーンを確認。レビュー承認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
