---
id: TASK-476.1
title: 独自ドメイン移行の方針を ADR にまとめる
status: Done
assignee: []
created_date: '2026-08-13 14:20'
updated_date: '2026-08-14 06:18'
labels:
  - site
dependencies: []
parent_task_id: TASK-476
priority: high
type: docs
ordinal: 101100
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
- [x] #1 ADR に workers.dev ホストの存続方針と、無期限で維持するパスが明記されている
- [x] #2 アプリ側 appcast URL を切り替えるか否かと、その理由・影響範囲が記録されている
- [x] #3 staging のホスト名とダッシュボードの保護方式（Access / Basic 認証）の決定が記録されている
- [x] #4 後続サブタスクの Acceptance Criteria が ADR の決定と矛盾しないよう更新されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 検証

- ADR: `docs/adr/0007-distribution-site-custom-domain.md`（番号 0007 を採った理由: 0006 は TASK-438.3 が libgit2 ADR に振り直す予定のため空けた）
- backlog decision: decision-7（本文は ADR を参照する形。decision-6 と同じ体裁）
- `markdownlint-cli2` を実行し 71 ファイル 0 issues を確認
- AC #4 の対象: TASK-476.2 / 476.3 / 476.4 / 476.6 は Description と Acceptance Criteria を差し替え、476.5 と親 476 は Notes に追記

## 決定を確定させた根拠の種別

- 実測: `rg -n "workers\.dev|tommy109"` の全ヒットを用途別に分類（本番コード 5 箇所 / テスト固定値 4 ファイル / 外部導線 / ドキュメント）
- コード参照: ADR 本文に file:line で記載
- ドキュメント参照: Cloudflare「workers.dev」「Access application paths」。**現行コードのコメント（`site/wrangler.toml:7`、`site/src/routes/dashboard.tsx:16`）が主張する「workers.dev には Access を設定できない」は現在のドキュメントに照らして誤り**であることを確認し、ADR に明記した
- 未確認: 実際の DNS 疎通・Access の動作・SSE の挙動は TASK-476.2 / 476.6 で実測する（ADR の「前提の裏付け」表に未確認として記載）

## backlog CLI の制約について

decision の本文を書くオプションが `backlog decision create` に無いため（`-s/--status` のみ）、decision-7 の Context / Decision / Consequences は生成後にファイルを直接編集した。decision-6 も同じ体裁で本文を持っている。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
独自ドメイン移行の 6 つの判断を ADR 0007（docs/adr/0007-distribution-site-custom-domain.md）と backlog decision-7 に確定した。workers.dev は全パス恒久維持、旧ホストのリダイレクトは LP と /features のみの肯定列挙、アプリの appcast URL とリリースの enclosure prefix は可搬性を理由に新ドメインへ切り替え、staging は staging.befold.degino.com、ダッシュボードは Access へ移して旧ホストの /dashboard は 404、自己参照の除外は自己ホスト集合へ変更。各決定に「破れたら落ちるもの」を表で対応付けた。決定に合わせて TASK-476.2/476.3/476.4/476.6 の Description と AC を差し替え、476.5 と親 476 に追記。markdownlint-cli2 で 71 ファイル 0 issues を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
