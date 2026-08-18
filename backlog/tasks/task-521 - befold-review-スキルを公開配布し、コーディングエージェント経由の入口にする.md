---
id: TASK-521
title: befold-review スキルを公開配布し、コーディングエージェント経由の入口にする
status: To Do
assignee: []
created_date: '2026-08-18 14:58'
labels: []
dependencies: []
priority: high
ordinal: 761000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
手元には Claude Code 用の befold-review スキル（Claude が書いた .md / .mmd をユーザーにレビュー依頼する直前に befold で開く）がある。これを公開配布すれば、「Claude Code で書いた設計書をきれいに読む」という文脈から befold が発見される。ターゲット層（コーディングエージェントが生成した文書を読む Mac 開発者）と動機が最も一致する導線であり、コンテンツを継続的に書き続ける必要がない点で他の集客手段より維持コストが低い。

配布形態（Claude Code プラグイン / 単体スキルのリポジトリ / befold リポジトリ同梱のいずれか）は着手時に決める。

未確認の前提:
- スキルの実体ファイルの置き場を特定できていない。セッションの利用可能スキル一覧には befold-review が出るが、リポジトリ内の .claude/skills/ には存在せず、~/.claude 配下の find でも見つからなかった。着手時にどこで定義されているかを先に確認する
- Claude Code のプラグイン配布に何が必要か（マニフェストの形式・配布方法）は未調査

配布時の注意: スキルは befold CLI がインストール済みの Mac を前提にしているため、未インストール環境での挙動（何も起きない / 案内が出る）を決めてから公開する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold-review スキルが第三者から取得・インストールできる形で公開されている
- [ ] #2 befold 未インストール環境での挙動が定義され、ユーザーに何をすればよいか伝わる
- [ ] #3 スキルの説明文から befold の配布サイトへ辿れる
- [ ] #4 配布形態の選定理由がタスクの Notes に記録されている
<!-- AC:END -->
