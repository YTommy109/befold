---
id: TASK-197
title: 配布サイト Worker のデプロイを main マージ時に自動化する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-30 00:07'
updated_date: '2026-07-30 01:55'
labels: []
dependencies:
  - TASK-196
priority: medium
ordinal: 280000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在 Worker のデプロイは手動の npx wrangler deploy で、D1 マイグレーションの適用（migrate:remote）も手動。この 2 手は順序を間違えると静かに壊れる。マイグレーションを先に当てないと新コードの INSERT がカラム不足で失敗し、insertEvent は例外を飲む設計のため計測が無言で欠落する（TASK-182.6 の実装時に実際にこの順序制約に直面した）。

人間の記憶に依存させず、main へのマージで migrate:remote → deploy の順に実行されるようにする。

前提と論点:
- GitHub Secrets に CLOUDFLARE_API_TOKEN を登録する必要があり、これはユーザーの操作。トークンを置きたくない場合は Cloudflare 側の Git 連携（Workers Builds）でリポジトリを繋ぐ代替がある。着手時にどちらを採るか確認する。
- マイグレーションの自動適用は前進のみ安全。カラム削除や型変更のような破壊的変更を自動で流すのは危険なので、破壊的変更を検知したら止める、あるいは破壊的変更だけ手動運用にする方針をあわせて決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 main へのマージで Worker が自動デプロイされる
- [x] #2 デプロイ前に D1 マイグレーションが適用され、順序が逆転しない
- [x] #3 site/ に変更が無いマージではデプロイが走らない
- [x] #4 破壊的なマイグレーションの扱い（自動適用するか止めるか）が決定され site/README.md に記載される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 認証方式は GitHub Actions + CLOUDFLARE_API_TOKEN（ユーザー判断で確定）。Workers Builds は採らない。マイグレーション先行・テスト通過を条件にする順序制御をリポジトリ内のコードとして残せるため。
2. 破壊的マイグレーションは検知して止める（ユーザー判断で確定）。scripts/check-destructive-migrations.sh を新設する。
3. ガードは『本番に未適用のマイグレーションだけ』を検査対象にする。全ファイルを見ると破壊的変更を一度手動適用した後も永久に落ち続ける。未適用判定は d1_migrations テーブルの name とファイル一覧の突き合わせで行う（wrangler d1 migrations list の表形式出力の解析は脆いので採らない）。
4. 既存 site.yml に deploy ジョブを足す。if で push かつ main に限定、needs: test でテスト通過を前提にし、concurrency group site-deploy（cancel-in-progress: false）で並行デプロイを避ける。
5. ステップ順は ガード → migrate:remote → deploy。
6. site/README.md に自動デプロイの説明、必要なトークン権限（Workers Scripts / Edit、D1 / Edit）、破壊的変更時の手動手順を記載する。
7. トークン登録はユーザーの操作。登録前は deploy ジョブが失敗するため、登録後に main への push で実挙動を確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
site.yml に deploy ジョブを追加（if で push かつ main 限定、needs: test、concurrency site-deploy）。ステップ順は 破壊的変更の検査 → migrate:remote → deploy。scripts/check-destructive-migrations.sh を新設し、本番に未適用のマイグレーションだけを走査して DROP / RENAME / DELETE FROM / TRUNCATE を検出する。

検証（run 30506867686、main b52304bf）:
#1 test success → deploy success。ログに Uploaded befold / Deployed befold triggers / Current Version ID: 5385dbd7-d5e5-4ee2-818d-adfd84052198。wrangler deployments list の最新が同 ID・01:53:23 で一致。デプロイ後の本番疎通は / 200、/download 302、/appcast.xml 200、/dashboard 401。
#2 ログでステップ順を確認: 『未適用のマイグレーションはありません』→『✅ No migrations to apply!』→ デプロイ。順序は if/needs ではなくステップ順で保証している。
#3 PR #326 では deploy が skipping（PR では本番に触れない）。backlog のみの PR #322 ではワークフロー自体が起動しないことを別途実測済み。
#4 破壊的変更は検知して止める方式を採用し、site/README.md に必要なトークン権限（Workers Scripts / Edit、D1 / Edit）と手動適用手順を記載。

途中で発生した問題と対処:
(a) 初回の deploy が jq: Cannot index object with number / exit 5 で失敗（run 30506166297）。真因は Secrets 名の綴り誤り（CLAUDFLARE_API_TOKEN として登録されていた）で、GitHub は名前不一致の Secrets を空文字として渡すため気づけなかった。ユーザーが正しい名前で再登録し誤登録分を削除。あわせてスクリプト側の診断を改善した（PR #325）。認証失敗時に原因の候補と wrangler の出力を出す、d1_migrations が無い DB を全件未適用として扱う、ヘアドキュメント内の $DB が全角文字まで変数名と解釈され set -u で落ちる不具合の修正。
(b) scripts/check-destructive-migrations.sh が site.yml の paths に無く、PR #325 のマージでワークフローが起動しなかった。deploy ジョブの実行時依存なので paths に個別指定で追加（PR #326）。scripts/** にしないのは worktree-clean.sh 等の無関係な変更で本番デプロイを走らせないため。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
main へのマージで D1 マイグレーション適用 → Worker デプロイの順に自動実行する deploy ジョブを site.yml に追加した。テスト通過を needs で前提化し、concurrency で並行デプロイを禁じ、破壊的なマイグレーション（DROP / RENAME / DELETE / TRUNCATE）は scripts/check-destructive-migrations.sh が本番未適用分だけを走査して検出しデプロイを止める。認証は GitHub Secrets の CLOUDFLARE_API_TOKEN。run 30506867686 で初回の自動デプロイが成功し、Version ID 5385dbd7 が wrangler deployments list の最新と一致、デプロイ後の本番疎通も確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
