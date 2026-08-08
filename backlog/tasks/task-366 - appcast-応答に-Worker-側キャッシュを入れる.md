---
id: TASK-366
title: appcast 応答に Worker 側キャッシュを入れる
status: To Do
assignee: []
created_date: '2026-08-08 08:55'
labels: []
dependencies: []
priority: low
ordinal: 627000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-355 で appcast の取得元が GitHub の fetch（cf: { cacheTtl: 300, cacheEverything: true }）から R2 の直読みに変わった。R2.get はリクエストごとに実行されるため、Sparkle のアップデートチェック 1 回につき R2 のクラス B 操作が 1 回発生する。

応答自体には Cache-Control: public, max-age=300 を付けているが、これはクライアント/中間キャッシュ向けであって Worker から R2 への読み出しは抑止しない。caches.default を使って Worker 側でも 300 秒キャッシュし、GitHub をプロキシしていたときと同じ性質に戻す。

計測（update_check の記録）はキャッシュヒット時も必ず走らせること。キャッシュを先に返して記録を飛ばすと、アップデート確認数が過小になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 /appcast.xml と /appcast-develop.xml が caches.default で 300 秒キャッシュされ、キャッシュヒット時に R2 を読まない
- [ ] #2 キャッシュヒット時も update_check が記録されることをテストで担保する
<!-- AC:END -->
