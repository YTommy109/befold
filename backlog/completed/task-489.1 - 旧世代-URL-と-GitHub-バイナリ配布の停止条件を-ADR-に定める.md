---
id: TASK-489.1
title: 旧世代 URL と GitHub バイナリ配布の停止条件を ADR に定める
status: Done
assignee:
  - '@claude'
created_date: '2026-08-16 02:00'
updated_date: '2026-09-04 02:13'
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
- [x] #1 3 種類の GitHub 配布停止（新規 DMG 添付 / appcast アップロード / 過去アセット削除）が別々の条件として定義されている
- [x] #2 workers.dev ホストの停止条件が定義されている
- [x] #3 各条件が観測可能な指標と継続期間で書かれている
- [x] #4 止めることで自動更新が切れる対象バージョンが条件ごとに明示されている
- [x] #5 ADR が backlog decisions と docs/adr の両方に既存の形式で追加され、ADR 0007 との関係（更新か supersede か）が明記されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
観測手段の担当は TASK-489.2 から TASK-488.3 へ移した（計測基盤の変更は TASK-488 側に集約する方針）。停止条件を書く際の観測手段の参照先は TASK-488.3。

停止条件を書く際、人間の訪問数がデータセンター由来の自動アクセスで膨らんでいる点に注意する（TASK-490 の実測: human visit 354 件のうち Meta / Amazon / Google / Twitter / Driftnet 等のデータセンター由来が 150 件規模）。旧ホストや GitHub 経路を「アクセスがゼロになったら止める」形にする場合、その 0 判定が誤ったボット分類の上に乗らないよう、TASK-490 の結論を前提にするか、条件側で ASN による検算を明示すること。

TASK-489.2 は起票されていなかった。観測手段を用意するタスクは **TASK-489.5**（旧世代の配布経路を停止判断できる形で観測する）として 2026-09-04 に起票した。Description 中の「TASK-489.2」はこれを指す。

ADR 0011（docs/adr/0011-legacy-distribution-shutdown-conditions.md）と decision-11 を追加し、ADR 0007 側にも更新の旨を 2 箇所（ヘッダの関連情報と決定 1 の該当段落）へ書いた。supersede ではなく更新。

起票時の想定から変わった点が 1 つある。**旧ホストの /appcast*.xml と /dl/* を別々の条件に分けた。** ADR 0007 は「配信済み appcast の enclosure URL は変更できない」を理由に両者を 1 つの『旧ホスト維持』へ畳んでいたが、実測（2026-09-04）では現行 appcast の enclosure 3 件がすべて befold.degino.com を指していた。generate_appcast が保持するのは直近 3 件で、旧ホストを指すエントリはもう残っていない。Sparkle はフィードを毎回取り直すのでクライアント側にも古い enclosure は残らず、旧ホストの download は全期間 0 件だった。つまり ADR 0007 が挙げた制約は現在は実効的に消えている。

指標の限界を 2 つ ADR に明記した。
- GitHub の appcast アセットの download_count は release.yml の gh release upload --clobber がリリースのたびに置き換えるためカウンタが 0 に戻る。条件 2 だけは期間ではなくリリース回数で数える形にせざるを得なかった
- GitHub のリリースアセットの download_count は Worker の /dl/ フォールバック（GitHub アセットへ 302）の分と混ざるため、直接アクセス分を取り出せない

検証: markdownlint-cli2 と scripts/check-doc-citations.sh をどちらも 0 件で通した（ADR には行番号引用を使っていない）。

TASK-489.4 側へ申し送りを AC として渡した（年 1 回の判定・未達なら To Do へ戻す、/dl と /appcast を分けて判断する）。依存も TASK-489.1 を追加した。

2026-09-04、ユーザー判断で決定 4a/4b の継続期間を 180 日／365 日から**どちらも 90 日**へ短縮し、決定 5 の判定間隔を年 1 回から四半期 1 回へ変更した。ADR と decision-11 の両方を更新済み。

365 日の当初根拠（月に一度しか開かないユーザーは 30 日の窓では観測されない）は観測の性質としては正しいが、**そこまで起動間隔が空くユーザーにとって自動更新は既に機能を果たしていない**という指摘で覆った。観測されない人を守るために経路を維持する理屈は、その人が経路から利益を得ている場合にのみ成立する。この判断は観測ではなく解釈であり、反例を否定できないことは ADR の Consequences に明記した。

母集団の実測を追加した: v1.10.1〜v1.12.3 の 11 リリースで GitHub DMG ダウンロード合計 19 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ADR 0011 と decision-11 を追加し、旧世代の配布経路の停止条件を 4 つに分けて定めた（GitHub の DMG 添付 / appcast アップロード / 過去アセット削除 / workers.dev）。条件はすべて『指標が人間分ゼロ + 継続期間 + 切り捨てるバージョン範囲の明示』の形で、切れる対象は決定 2 が v1.10.0 以前、決定 4b が v1.10.1〜v1.12.x、他は無し。過去アセットの削除は『原則削除しない』を結論とした。ADR 0007 の決定 1 を更新する形で、0007 側にも参照を入れてある。実測（D1 の events・GitHub Releases API・現行 appcast の enclosure）で各指標の現在値と限界を裏付けた。検証: markdownlint-cli2 / check-doc-citations.sh ともゼロ件。判定の実施は TASK-489.4 へ AC として渡した。
<!-- SECTION:FINAL_SUMMARY:END -->
