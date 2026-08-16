---
id: TASK-489.2
title: 旧ホストと GitHub 直経路へのアクセスを観測できるようにする
status: To Do
assignee: []
created_date: '2026-08-16 02:00'
updated_date: '2026-08-16 02:07'
labels: []
milestone: m-8
dependencies:
  - TASK-488.1
parent_task_id: TASK-489
priority: medium
ordinal: 722000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-489 の停止判断に必要な数字を取れるようにする。TASK-489.1 が定める条件は、この計測が無いと永久に判定できない。

現状 `events` テーブルにはホストもパスも列が無く（`site/schema/schema.sql:5-26`）、リクエストがどのホストに来たのかを記録していない。そのため次が数えられない。

- `befold.tommy109.workers.dev/appcast.xml` へのアクセス数（旧ホスト停止条件の根拠）
- GitHub 直の appcast（`https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml`）を見ている v1.10.0 以前のクライアント数。※ これはサイトを経由しないため Worker では観測できない。GitHub のリリースアセットのダウンロード数 API など、別の観測手段を検討すること
- R2 ミスによる GitHub フォールバックの発生数（`site/src/routes/public.tsx:73-76` の 302、`site/src/lib/github.ts:10-12` の appcast プロキシ）。ここが 0 でないうちは GitHub を止められない

`update_check` イベントは既に記録されている（`site/src/routes/public.tsx:146`）ので、ホストの次元を足せば旧ホスト分は分離できる。TASK-488.1 がページの記録でスキーマに触るため、**列の設計はそちらと重複させないこと**（同じマイグレーションにまとめるか、後続で足すかを判断する）。

ボット判定は既存の `ua_summary` の `bot:` 接頭辞を流用する（`site/src/lib/visitor.ts:104-123`）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 リクエスト先ホスト（旧ホスト / 正規ホスト）が events に記録される
- [ ] #2 旧ホストの appcast アクセス数が人間とロボットに分けてダッシュボードで確認できる
- [ ] #3 R2 ミスによる GitHub フォールバックの発生が観測できる
- [ ] #4 GitHub 直 appcast を見ているクライアントの観測手段について、可否と方法が調査結果として記録されている
- [ ] #5 TASK-488.1 のスキーマ変更と列設計が重複していない
- [ ] #6 site の vitest と typecheck が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-488.3 へ移動したためアーカイブする。計測基盤（events のスキーマ・ダッシュボード）に関する変更は TASK-488 側へ集約する方針（ユーザー判断、2026-08-16）。内容は TASK-488.3 に引き継いだ。
<!-- SECTION:NOTES:END -->
