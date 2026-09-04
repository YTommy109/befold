---
id: TASK-489.4
title: 条件を満たした旧世代の配布経路を実際に停止する
status: To Do
assignee: []
created_date: '2026-08-16 02:01'
updated_date: '2026-09-04 02:13'
labels: []
milestone: m-8
dependencies:
  - TASK-489.1
parent_task_id: TASK-489
priority: low
type: chore
ordinal: 724000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-489 の実行フェーズ。**条件が満たされるまで着手しない。**

TASK-489.1 が定めた停止条件を、TASK-489.2 が用意した観測結果に照らして評価し、満たしたものから順に止める。止める対象は次の 4 つで、それぞれ独立に判断する。

1. 新規リリースでの GitHub Releases への DMG 添付（`.github/workflows/release.yml:212-216`）
2. 固定リリース `appcast` への appcast アップロード（同 :308-316）。**先行作業として `gh release download appcast` を入力に使っている箇所（同 :289,300 付近）を R2 からの取得に置き換える必要がある**
3. Worker の GitHub フォールバック経路（`site/src/lib/github.ts:10-12` の `APPCAST_UPSTREAM`、`site/src/routes/public.tsx:73-76` の 302、`/download` の GitHub API 経路）
4. workers.dev ホスト（`site/wrangler.toml` の `workers_dev = true` を false へ、`site/src/lib/hosts.ts` の LEGACY 定数と 301 ミドルウェア、旧ホスト向けテストの整理）

## 着手できる条件

TASK-489.1 の ADR が存在し、TASK-489.2 の観測でその条件を満たしたことが確認できていること。**観測を待たずに止めない。** ADR 0007 が指摘するとおり、出荷済みアプリの Sparkle フィード URL と配信済み appcast の enclosure URL は後から変更できないため、止めた時点でその経路のクライアントは自動更新を失う（`docs/adr/0007-distribution-site-custom-domain.md:29-44`）。

過去のリリースアセットの削除は、TASK-489.1 で「原則削除しない」と結論した場合はここでも実施しない。

## 停止後に必要な後始末

- ADR 0007 の「破れたら落ちるものの担保表」に載っているテスト（`workers_dev = true` の存置テスト `site/test/wrangler-config.test.ts:26-28`、旧ホストの appcast・`/dl/` が 200 であることのテスト `site/test/public.test.ts:586-660`）は、停止と同じ変更で意図的に書き換える。**テストが赤いまま放置しない。**
- 停止した経路と日付を ADR に追記する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 停止した対象ごとに、満たした条件と観測値が記録されている
- [ ] #2 GitHub の appcast を入力に使っていた箇所が R2 からの取得に置き換わっている（appcast アップロードを止める場合）
- [ ] #3 停止に伴い意味が変わったテストが、意図を反映した形に書き換えられている
- [ ] #4 停止した経路と日付が ADR に追記されている
- [ ] #5 条件を満たさなかった対象は止めずに残り、その理由が記録されている
- [ ] #6 判定は年 1 回行い、条件を満たさなかった対象があるうちはタスクを To Do に戻して次回判定日を Notes に書く（ADR 0011 の決定 5）
- [ ] #7 旧ホストの /dl/* と /appcast*.xml は別々に判断する。前者を止めるために後者を待たない（ADR 0011 の決定 4）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手不可。TASK-489.1（停止条件の ADR）と TASK-489.2（観測）の両方が完了し、観測値が条件を満たしたことを確認できるまで着手しない。再開判断の材料: ダッシュボードで旧ホストの appcast アクセスと GitHub フォールバック発生数が条件どおりゼロ継続しているか。

TASK-489.2 は起票されていなかった。観測は **TASK-489.5** が用意する。Description・Notes 中の「TASK-489.2」はこれを指す（依存にも追加済み）。

TASK-489.1 で ADR 0011（docs/adr/0011-legacy-distribution-shutdown-conditions.md / decision-11）を書き、4 つの停止条件が確定した。Description の「1〜4 の対象」と ADR の決定番号の対応は次のとおり。

- Description 1（DMG 添付）→ ADR 0011 決定 1
- Description 2（appcast アップロード）→ 決定 2。先行作業（gh release download appcast を R2 へ）は ADR でも未起票と明記した
- Description 3（Worker の GitHub フォールバック）→ 決定 1・決定 3 の指標として使う側であり、ADR は「フォールバック経路そのものを止める」条件を定めていない。R2 を正としたまま残す前提
- Description 4（workers.dev）→ 決定 4。ただし ADR は /dl/* (4a) と /appcast*.xml (4b) に分割した

2026-09-04 時点の実測（判定の出発点。いずれも条件未達）:
- 旧ホストの update_check: 最終 2026-08-21（1.12.0 と 1.12.3-dev.10 の 2 件のみ）。365 日連続ゼロの条件に対し 14 日
- 旧ホストの download（/dl/）: host 列導入以降の全期間で 0 件。180 日連続ゼロの条件に対し 19 日
- GitHub の appcast アセット download_count: 両方 0（ただし直近リリース 2026-09-02 でリセット済み。リリース 3 回のうち 1 回目）
- github_fallback の dmg: 人間分ほぼゼロだが完全な 0 ではない（Safari 14 件。登録組織はシンガポールの proxy 住所）

次回判定日: 2027-09-04。

停止条件を短縮した（2026-09-04、ユーザー判断）。旧ホストの条件は 4a/4b とも **90 日**連続ゼロ。判定間隔も年 1 回から四半期 1 回へ。

根拠: 切り捨てる母集団（v1.10.1〜v1.12.x）は 11 リリースで GitHub DMG ダウンロード合計 19 件（最大 v1.11.6 の 5 件。Worker の /dl/ フォールバック分と混在するため実人数はこれ未満）。加えて、90 日を超えて観測されない使い方では自動更新そのものが機能を果たしていない（起動しない限りチェックも更新も走らない）。

**次回判定日を 2026-11-19 に変更する**（旧ホストの最終 update_check 2026-08-21 の 90 日後）。前の Notes に書いた 2027-09-04 は無効。

4a を 180 日から 90 日へ下げたのは 4b と揃えるため。4b は 4a の充足を要求するので、4a が長いと 4b の期間指定が意味を失う。
<!-- SECTION:NOTES:END -->
