---
id: TASK-476.1
title: 独自ドメイン移行の方針を ADR にまとめる
status: To Do
assignee: []
created_date: '2026-08-13 14:20'
labels:
  - site
dependencies: []
parent_task_id: TASK-476
priority: high
ordinal: 100200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold.degino.com への移行で先に確定させるべき判断を ADR（site/docs/adr/）に残す。実装より先に着手する。

決めること:
1. workers.dev ホストの扱い（恒久維持 / 一部パスのみ維持 / いつ止めるか）。出荷済みアプリの Sparkle フィード URL は変更できないため、少なくとも /appcast*.xml と /dl/ は無期限で旧ホストでも 200 を返し続ける必要がある。
2. 旧ホストの LP・ダッシュボードを 301 で新ドメインへ送るか。送る場合、リダイレクト対象から appcast・/dl/ を除外する条件をどう表現するか（Sparkle はリダイレクトを追うが、ダウンロード計測とキャッシュの扱いに影響する）。
3. アプリ側の appcast URL を新ドメインへ切り替えるか。切り替えても効くのは切り替え後のバージョンを入れたユーザーのみで、旧ホストへのアクセスは永続する。
4. staging のホスト名（staging.befold.degino.com か workers.dev のままか）。
5. ダッシュボードの保護方式（ゾーン配下になるため Cloudflare Access が使える。現行は Basic 認証）。
6. 計測の連続性: 新旧ホスト間の遷移を「外部参照元」として記録しないための自己ホスト集合の扱い。

各判断は「既存ユーザーの更新経路を壊さない」を最優先の制約として書く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ADR に workers.dev ホストの存続方針と、無期限で維持するパスが明記されている
- [ ] #2 アプリ側 appcast URL を切り替えるか否かと、その理由・影響範囲が記録されている
- [ ] #3 staging のホスト名とダッシュボードの保護方式（Access / Basic 認証）の決定が記録されている
- [ ] #4 後続サブタスクの Acceptance Criteria が ADR の決定と矛盾しないよう更新されている
<!-- AC:END -->
