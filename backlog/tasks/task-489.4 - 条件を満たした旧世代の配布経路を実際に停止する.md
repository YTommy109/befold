---
id: TASK-489.4
title: 条件を満たした旧世代の配布経路を実際に停止する
status: To Do
assignee: []
created_date: '2026-08-16 02:01'
updated_date: '2026-08-17 14:52'
labels: []
milestone: m-8
dependencies:
  - TASK-489.1
  - TASK-488.3
  - TASK-495
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
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手不可。TASK-489.1（停止条件の ADR）と TASK-489.2（観測）の両方が完了し、観測値が条件を満たしたことを確認できるまで着手しない。再開判断の材料: ダッシュボードで旧ホストの appcast アクセスと GitHub フォールバック発生数が条件どおりゼロ継続しているか。
<!-- SECTION:NOTES:END -->
