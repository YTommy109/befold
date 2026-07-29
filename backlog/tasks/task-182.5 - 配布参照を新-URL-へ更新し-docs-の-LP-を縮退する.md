---
id: TASK-182.5
title: 配布参照を新 URL へ更新し docs/ の LP を縮退する
status: In Progress
assignee:
  - '@Tommy109'
created_date: '2026-07-28 13:36'
updated_date: '2026-07-29 23:55'
labels: []
dependencies:
  - TASK-182.6
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
parent_task_id: TASK-182
priority: low
ordinal: 262000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README や関連ドキュメントの配布 URL を新 Worker の URL に更新する。Worker の安定稼働を確認した後、docs/ の LP 部分（index.html 等）を開発ドキュメント専用へ縮退する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 README 等の配布リンクが新 Worker URL を指す
- [ ] #2 docs/ の LP 部分が縮退され役割が site/ へ移る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. docs/index.html を配布サイトへのリダイレクト 1 枚に置換する。meta refresh + JS location.replace + 手動リンクのフォールバックを併置し、遷移先は https://befold.tommy109.workers.dev/?ref=gh-pages とする（TASK-182.6 の参照元計測に載せるため）。CSS は外部ファイルを消すのでインライン最小限にする。
2. docs/style.css・docs/carousel.js・docs/images/（スクリーンショット 5 枚）を削除する。site/public/ に同一バイトサイズの資産が揃っており重複のため。docs/index.html 以外からの参照が無いことを grep で確認済み。
3. docs/adr/・docs/dev/・docs/superpowers/ は開発ドキュメントなので残す。_config.yml の exclude: [superpowers] も維持する。
4. ルート README.md:6 の紹介ページリンクを新 URL へ差し替える。
5. リダイレクトが実際に効くかを Chrome で検証する（Pages の反映後）。
<!-- SECTION:PLAN:END -->
