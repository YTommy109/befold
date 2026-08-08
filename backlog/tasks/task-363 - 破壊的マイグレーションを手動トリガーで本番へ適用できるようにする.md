---
id: TASK-363
title: 破壊的マイグレーションを手動トリガーで本番へ適用できるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 07:49'
updated_date: '2026-08-08 08:01'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 624000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
破壊的なマイグレーション（DROP / RENAME / DELETE FROM / TRUNCATE を含むもの）は scripts/check-destructive-migrations.sh が CI の自動デプロイを止める設計になっている（.github/workflows/site.yml、site/README.md）。この歯止め自体は妥当だが、解除手段がローカルからの npm run migrate:remote しかなく、実行者に wrangler の認証が要る。

実際に TASK-362（ts / visitor_day の改名）で詰まった。Claude Code の ! 実行は非対話シェルのため wrangler が OAuth ログインを開けず、'In a non-interactive environment, it's necessary to set a CLOUDFLARE_API_TOKEN environment variable' で失敗する。対話的なターミナルへ移って npx wrangler login から実行し直す必要があった。

site.yml には workflow_dispatch が無く（rg で確認、workflow_dispatch を持つのは verify-dmg.yml のみ）、CI 側の CLOUDFLARE_API_TOKEN を使ってマイグレーションだけを流す手段が無い。

手動トリガーであること自体が『人が内容を確認した』という歯止めになるため、自動デプロイを止める設計とは矛盾しない。マイグレーション適用専用のワークフローを workflow_dispatch で用意する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 workflow_dispatch でマイグレーションのみを本番 D1 へ適用できるワークフローがある
- [x] #2 適用対象のデータベース（本番 / staging）を入力で選べる
- [x] #3 実行前に未適用のマイグレーション一覧がログに出る（何が当たるか分からないまま実行できない）
- [x] #4 通常の push による自動デプロイ経路では、破壊的マイグレーションが引き続き check-destructive-migrations.sh で止まる（歯止めが迂回されていない）
- [x] #5 手順が site/README.md に記載され、ローカルからの npm run migrate:remote との使い分けが分かる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. .github/workflows/site-migrate.yml を新設する（site.yml には手を入れない）
   - トリガーは workflow_dispatch のみ。push / schedule / workflow_call は持たせない（deploy 側から呼べると歯止めが迂回される）
   - 将来 push トリガーを足されても気づけるよう、github.event_name != 'workflow_dispatch' なら落ちるガードを入れる
2. 入力: environment（production / staging）、mode（plan / apply）、confirm
   - plan は未適用一覧を出すだけ。apply が実際に当てる
   - 本番へ apply するときだけ confirm にデータベース名の入力を要求する
   - confirm はシェルへ直接展開せず env 経由で渡す（式のスクリプトインジェクション回避）
3. concurrency group を deploy ジョブと同じ site-deploy にする
   - マイグレーションとデプロイが同時に走るとスキーマと Worker の版が食い違うため、別グループにしない
4. 未適用一覧は wrangler d1 migrations list <db> --remote で取る
   - apply と同じ情報源にする（plan が出したものと当たるものが一致することを保証する）
   - npm script 化して手元からも同じコマンドで確認できるようにする
5. 適用対象が無い場合は成功で終える（何もしないことがログから分かる形にする）
6. site/README.md に手順と、ローカルからの npm run migrate:remote との使い分けを書く

設計上の判断:
- 自動デプロイ経路（site.yml）の check-destructive-migrations.sh には一切触れない。歯止めは残したまま、解除手段だけを増やす
- 手動トリガーであること自体を『人が内容を確認した』証跡とみなす。これは check-destructive-migrations.sh のメッセージが求めている手順と同じ
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-08 実装完了。

.github/workflows/site-migrate.yml（新規、site.yml には一切触れていない）:
- トリガーは workflow_dispatch のみ。push / schedule / workflow_call を持たせない（deploy 側から呼べると歯止めが迂回されるため）
- 将来 push などのトリガーを足されても黙って自動適用に変わらないよう、github.event_name != 'workflow_dispatch' で落ちるガードを先頭に置いた
- 入力: environment（production / staging、既定 staging）、mode（plan / apply、既定 plan）、confirm
- 本番へ apply するときだけ confirm にデータベース名 befold-analytics を要求する。confirm は式でシェルへ直接展開せず env 経由で渡す（スクリプトインジェクション回避）
- concurrency group を deploy ジョブと同じ site-deploy にした。マイグレーションと Worker デプロイが同時に走るとスキーマと配信中コードの版が食い違うため
- 未適用一覧は wrangler d1 migrations list（npm run migrate:list / migrate:list:staging）で取る。plan と apply で情報源を分けないことで、plan で見たものと当たるものがずれない
- 最後に mode に応じた要約を出す（plan のみか、適用後に Site CI 再実行が要るか）

package.json: migrate:list / migrate:list:staging を追加。手元からも同じコマンドで未適用を確認できる。

site/README.md: 「破壊的なマイグレーションは自動適用されない」の節に適用手段を 2 つ（GitHub Actions 推奨 / ローカル）並べ、非対話シェルでローカル実行が失敗する理由を明記した。あわせて文脈から外れていた Atlas の型変更の段落を元の位置へ戻した。

検証: actionlint が全ワークフローでエラーなし（exit 0）、markdownlint-cli2 が 0 issues。

未検証: ワークフローの実行そのもの。workflow_dispatch は main に載るまで Actions から起動できないため、マージ後に mode: plan（何も適用しない）で 1 回試すのが最初の実地確認になる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
D1 マイグレーションだけを手動適用する専用ワークフロー Site Migrate を新設した。CI 側の CLOUDFLARE_API_TOKEN を使うため、非対話シェルで wrangler の OAuth ログインを開けない問題を回避できる。site.yml の check-destructive-migrations.sh には触れておらず、自動デプロイ経路の歯止めは残したまま解除手段だけを増やしている。plan / apply を入力で分け、本番 apply にはデータベース名の確認入力を課し、concurrency group を deploy と共有して版の食い違いを防いだ。actionlint / markdownlint ともエラーなし。ワークフローの実行自体はマージ後に mode: plan で確認する。
<!-- SECTION:FINAL_SUMMARY:END -->
