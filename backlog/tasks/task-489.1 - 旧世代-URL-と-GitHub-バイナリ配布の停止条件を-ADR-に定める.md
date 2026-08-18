---
id: TASK-489.1
title: 旧世代 URL と GitHub バイナリ配布の停止条件を ADR に定める
status: To Do
assignee: []
created_date: '2026-08-16 02:00'
updated_date: '2026-08-17 14:52'
labels: []
milestone: m-8
dependencies: []
parent_task_id: TASK-489
priority: medium
type: task
ordinal: 721000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-489 の前提を作るサブタスク。何を満たしたら止めてよいかを先に決める。

ADR 0007（`docs/adr/0007-distribution-site-custom-domain.md`）は workers.dev の恒久併存を決め、停止条件を「旧ホストの appcast を叩くクライアントがゼロになったこと。ただし観測できてもゼロを保証できない」と書いたうえで停止時期を定めていない（:117-118）。この判断自体は出荷済みバイナリの制約から正しいが、**観測すらしていない現状では、条件を満たしたかどうかを永久に判定できない**。

このタスクで、ADR 0007 を更新する新しい ADR を書き、次の 3 つを別々の条件として定める。ひとつの「停止」に畳まないこと。リスクの大きさが桁違いに違う。

1. **新規リリースでの GitHub Releases への DMG 添付をやめる条件**（比較的軽い。既存アセットは残るため過去版の更新は壊れない）
2. **固定リリース `appcast` への appcast アップロードをやめる条件**（`release.yml` がこれを入力にも使っているため、入力を R2 へ移す先行作業が要る。止めると v1.10.0 以前のクライアントの自動更新が切れる）
3. **過去のリリースアセットを削除する条件**（最も危険。配信済み appcast の enclosure が GitHub 直リンクのまま書き換えられないため、削除するとその版からの更新ダウンロードが 404 になる。原則削除しない、という結論もありうる）

あわせて **workers.dev ホストの停止条件**（`workers_dev = false` にする条件）も定める。

条件は「観測できる指標 + 継続期間」の形にする（例: 旧ホストの `/appcast.xml` へのアクセスが人間・ロボットとも 0 件の状態が N か月継続）。観測手段は TASK-489.2 が用意する。ゼロを保証できないという ADR 0007 の指摘は正しいので、**「ゼロが続いたら止める」ではなく「ゼロが続いたうえで、切れても構わないと判断する版を明示して止める」形**にすること。

参考: 現在 GitHub に依存している箇所は親タスク TASK-489 の説明に列挙してある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 3 種類の GitHub 配布停止（新規 DMG 添付 / appcast アップロード / 過去アセット削除）が別々の条件として定義されている
- [ ] #2 workers.dev ホストの停止条件が定義されている
- [ ] #3 各条件が観測可能な指標と継続期間で書かれている
- [ ] #4 止めることで自動更新が切れる対象バージョンが条件ごとに明示されている
- [ ] #5 ADR が backlog decisions と docs/adr の両方に既存の形式で追加され、ADR 0007 との関係（更新か supersede か）が明記されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
観測手段の担当は TASK-489.2 から TASK-488.3 へ移した（計測基盤の変更は TASK-488 側に集約する方針）。停止条件を書く際の観測手段の参照先は TASK-488.3。

停止条件を書く際、人間の訪問数がデータセンター由来の自動アクセスで膨らんでいる点に注意する（TASK-490 の実測: human visit 354 件のうち Meta / Amazon / Google / Twitter / Driftnet 等のデータセンター由来が 150 件規模）。旧ホストや GitHub 経路を「アクセスがゼロになったら止める」形にする場合、その 0 判定が誤ったボット分類の上に乗らないよう、TASK-490 の結論を前提にするか、条件側で ASN による検算を明示すること。
<!-- SECTION:NOTES:END -->
