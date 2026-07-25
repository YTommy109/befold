---
id: TASK-143
title: ad-hoc 署名の dev ビルドでは CLI が ACK を観測できず転送検証ができない
status: To Do
assignee: []
created_date: '2026-07-25 06:50'
updated_date: '2026-07-25 06:51'
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
- [ ] #1 dev ビルド(ad-hoc 署名)の befold-cli から起動中インスタンスへ転送したとき、exit 0 で成功する。または終了コードで検証できない理由と代替の検証手順が docs に残っている
- [ ] #2 ACK を観測できない原因(署名/entitlement のどの差か)が特定され、タスクに記録されている
<!-- AC:END -->
