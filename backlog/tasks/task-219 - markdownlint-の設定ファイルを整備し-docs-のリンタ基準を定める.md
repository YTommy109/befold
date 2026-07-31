---
id: TASK-219
title: markdownlint の設定ファイルを整備し docs のリンタ基準を定める
status: To Do
assignee: []
created_date: '2026-07-31 08:40'
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
- [ ] #1 リポジトリルートに markdownlint の設定ファイルが置かれ、採用/除外したルールとその理由がコメントまたは docs に記録されている
- [ ] #2 採用したルールで既存の docs/ 配下と .claude/CLAUDE.md・ルート直下の Markdown が全て通る
- [ ] #3 docs 変更時にリンタを実行する手順が判る状態になっている（コマンドが CLAUDE.md か docs に記載、または CI/フックに組み込まれている）
<!-- AC:END -->
