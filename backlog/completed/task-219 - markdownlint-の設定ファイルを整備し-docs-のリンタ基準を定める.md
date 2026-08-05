---
id: TASK-219
title: markdownlint の設定ファイルを整備し docs のリンタ基準を定める
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 08:40'
updated_date: '2026-07-31 08:53'
labels:
  - chore
dependencies: []
priority: low
ordinal: 299000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
リポジトリに .markdownlint 系の設定ファイルが存在せず、markdownlint-cli2（v0.23.1 / markdownlint v0.41.1、ローカルにインストール済み）をデフォルトルールで実行すると main 時点で 327 件のエラーが出る。ルール別内訳は MD013/line-length 115、MD060/table-column-style 114、MD032/blanks-around-lists 25、MD022/blanks-around-headings 21、MD040/fenced-code-language 20、MD024/no-duplicate-heading 19、MD007/ul-indent 10、ほか少数。

このうち MD013（既定 80 文字上限）は日本語ドキュメントでは実質的に守れず、MD060（テーブルのパイプ前後の空白）と MD024（同名見出しの重複）も本文書群の書き方と全面的に衝突する。つまり既定値はこのプロジェクトの実態に合っておらず、現状は「設定がないので誰も lint を回さない」状態になっている。実際 TASK-214 / 215 / 216 の docs 作業ではいずれもリンタ検証を省いた。

一方 MD040（コードブロックの言語指定）のように実益のあるルールもある。MD040 が効いていれば viewer-rendering-dataflow.md の言語指定なしコードブロックは検出できた。

設定ファイルを置いて「このプロジェクトで守るルール」を確定させ、docs 変更時に実行できる状態にする。既存文書を全面修正するのがゴールではなく、採用したルールで既存文書が通ることまでを範囲とする（採用ルールに対する既存違反が少数なら修正し、多数なら当該ルールを見送る）。

参考: TASK-214/215/216 の各 PR (#359 / #362 / #363) では、設定なしのデフォルト実行で main 比のエラー総数が減っていることのみ確認した。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 リポジトリルートに markdownlint の設定ファイルが置かれ、採用/除外したルールとその理由がコメントまたは docs に記録されている
- [x] #2 採用したルールで既存の docs/ 配下と .claude/CLAUDE.md・ルート直下の Markdown が全て通る
- [x] #3 docs 変更時にリンタを実行する手順が判る状態になっている（コマンドが CLAUDE.md か docs に記載、または CI/フックに組み込まれている）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 対象範囲（docs/adr, docs/dev, ルート *.md, .claude/CLAUDE.md）でルール別違反件数を実測する
2. 生成物（backlog/, docs/superpowers/, CHANGELOG.md, node_modules）を ignore に入れる
3. 違反件数が多い/日本語文書と衝突するルール（MD013, MD060, MD041）を無効化し理由をコメントで残す
4. 残る少数違反ルール（MD040, MD007, MD032, MD024, MD005, MD022）は採用し既存違反を修正する
5. .markdownlint-cli2.jsonc をルートに置き markdownlint-cli2 が終了コード0になることを確認
6. .claude/CLAUDE.md のコマンド節に実行コマンドを1行追記する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（対象: docs/adr, docs/dev, ルート *.md, .claude/CLAUDE.md / 計 326 件）: MD060=116, MD013=114, MD032=25, MD022=21, MD024=19, MD040=18, MD007=10, MD041=2, MD005=1。うち MD022/MD032/MD024 の大半（21/21/18）は自動生成される CHANGELOG.md に集中していたため、CHANGELOG.md・backlog/・docs/superpowers/ を生成物として ignore に追加。結果として無効化が必要なのは MD013（日本語で 80 文字上限は非現実的）・MD060（日英混在でパイプ揃えが破綻）・MD041（CLAUDE.md / AGENTS.md は H1 を持たない指示ファイル）の 3 つのみとなり、他は既定どおり採用して既存違反 34 件を修正した。検証: markdownlint-cli2 が 13 ファイルで 0 issues / 終了コード 0。

【スコープ拡大: レビューでの判断】当初 globs は AC 準拠の 13 ファイル（ルート *.md / .claude/CLAUDE.md / docs/adr / docs/dev）だったが、.claude/agents・commands・skills 配下の指示ファイル約 37 件が手書き管理にもかかわらず対象外になっていた。実測で 48 件の違反（MD032 22 / MD040 11 / MD031 9 / MD022 4 / MD029 2）を確認し、いずれも描画崩れに直結する実益のあるルールだったため globs に .claude/agents|commands|skills と site/ を追加した。37 件は --fix で自動修正、残る MD040 11 件は中身に応じて手で言語指定（コミットメッセージ雛形は text、レビュー出力テンプレートは markdown、シェル例は bash）。MD029 の修正は release-notes.md の採番ミス（3. が 2 回続く）の是正で、内容の改善を伴う。最終: 52 files / 0 issues / 終了コード 0。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
リポジトリルートに .markdownlint-cli2.jsonc を追加し、採用/無効化したルールと理由を JSONC コメントで記録した。無効化は MD013 / MD060 / MD041 の 3 つのみで、生成物（backlog/, docs/superpowers/, CHANGELOG.md）は lint 対象外にした。採用ルールに対する既存違反 34 件（MD040 18, MD007 10, MD032 4, MD024 1, MD005 1）を 8 ファイルで修正し、markdownlint-cli2 が終了コード 0（13 ファイル 0 issues）になることを確認した。実行コマンドは .claude/CLAUDE.md の「コマンド」節に 2 行追記した。
<!-- SECTION:FINAL_SUMMARY:END -->
