---
id: TASK-238
title: Help > AI コーディングエージェント連携 のサンプル skill を実用に耐える内容へ直す
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 12:21'
updated_date: '2026-07-31 23:14'
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
- [x] #1 サンプル skill の description に発動条件(Use when ...)が含まれ、エージェントがユーザーへレビューを依頼する場面を指している
- [x] #2 サンプル skill の本文が、いつ使うか・何をするかの指示文として読める形になっている(コマンド 1 行だけではない)
- [x] #3 aiIntegration.detail の日本語・英語が新しい向きの説明になっている
- [x] #4 パネルの表示崩れがない(サンプルが縦に伸びすぎない)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. サンプル skill を、実運用中の ~/.claude/skills/befold-review/SKILL.md を圧縮した形に書き直す(description に Use when ... の発動条件、本文に「いつ使うか」「手順」)
2. AIIntegrationView.swift の exampleSkill を差し替える
3. Localizable.xcstrings の aiIntegration.detail を新しい向き(エージェントが書いた md をユーザーにレビュー依頼する直前に開く)に日英とも書き換える
4. ビルド + 起動して Help パネルの表示崩れを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
サンプルは運用中の ~/.claude/skills/befold-review/SKILL.md を圧縮した内容にした(frontmatter の description に Use when 条件、本文に When to use / Steps)。1 行 58 文字以内に折り返し、パネルの contentSize を 520x560 / minSize 440x320 に拡大。Debug ビルドを起動し Help > AI Coding Agent Integration をスクリプトで開いてスクリーンショット確認: 折り返し・スクロールなしで全文が収まる。swift test 1001 件パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Help > AI コーディングエージェント連携 のサンプル skill を、エージェントが書いた .md をユーザーにレビュー依頼する直前に開く向きへ書き直した。description に発動条件(Use when ...)を入れ、本文を When to use / Steps の指示文にし、aiIntegration.detail の日英も同じ向きに更新。パネルは contentSize 520x560 に拡大し、実機スクリーンショットで表示崩れがないことを確認。swift test 1001 件パス。
<!-- SECTION:FINAL_SUMMARY:END -->
