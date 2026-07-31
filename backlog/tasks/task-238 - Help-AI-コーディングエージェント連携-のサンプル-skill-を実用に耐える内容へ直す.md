---
id: TASK-238
title: Help > AI コーディングエージェント連携 のサンプル skill を実用に耐える内容へ直す
status: To Do
assignee: []
created_date: '2026-07-31 12:21'
updated_date: '2026-07-31 12:22'
labels:
  - refactor
dependencies: []
references:
  - BefoldApp/befold/App/AIIntegrationView.swift
  - BefoldApp/befold/Resources/Localizable.xcstrings
priority: low
ordinal: 441000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Help メニューの「AI コーディングエージェント連携」パネル(AIIntegrationView.swift:5-12 の exampleSkill と Localizable.xcstrings の aiIntegration.detail)が示すサンプル skill に 3 つの問題がある。(1) 発動の向きが逆: 「レビュー対象ファイルを開いてからコメントする」= ユーザーがエージェントにレビューを依頼した場面を想定しているが、エージェントはファイルを直接読むためビューアで開いても意味がない。正しくは「エージェントが書いた/更新した .md をユーザーにレビュー依頼する直前に開く」で、ユーザーが raw Markdown でなくレンダリング結果を見て判断できることに価値がある。(2) サンプルが skill の体をなしていない: frontmatter の直後に command -v befold の 1 行があるだけで、手順も「いつ使うか」も無く、シェルスクリプトの断片に見える。(3) description に発動条件が無い: skill が選ばれるかは description の "Use when ..." が実質決めるが、目的しか書かれておらず発動が不安定になる。実際にこのサンプル由来の skill が期待した場面で発動しない事例が確認されている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サンプル skill の description に発動条件(Use when ...)が含まれ、エージェントがユーザーへレビューを依頼する場面を指している
- [ ] #2 サンプル skill の本文が、いつ使うか・何をするかの指示文として読める形になっている(コマンド 1 行だけではない)
- [ ] #3 aiIntegration.detail の日本語・英語が新しい向きの説明になっている
- [ ] #4 パネルの表示崩れがない(サンプルが縦に伸びすぎない)
<!-- AC:END -->
