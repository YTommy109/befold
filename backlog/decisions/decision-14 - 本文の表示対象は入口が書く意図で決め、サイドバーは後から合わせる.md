---
updated_date: '2026-11-25T12:56:16Z'
id: decision-14
title: 本文の表示対象は入口が書く意図で決め、サイドバーは後から合わせる
date: '2026-11-25T00:12:07Z'
status: accepted
---
## Context

<!-- SECTION:CONTEXT:BEGIN -->
本文の表示（PreviewTarget）をサイドバーの選択と一覧の行から導いているため、行の着地が遅れると本文がフォルダー一覧へ落ちる。TASK-445・TASK-468・GitHub #794 と同型が 3 回続いた。詳細は docs/adr/0013-presentation-intent-before-sidebar-sync.md
<!-- SECTION:CONTEXT:END -->

## Decision

<!-- SECTION:DECISION:BEGIN -->
窓ごとに意図（文書 URL かフォルダー URL）を 1 つの値で持ち、利用者の操作を受けた入口だけが書く。PreviewTarget は意図から導き、サイドバーの同期は意図を書かない。フォルダーに入る・befold <ディレクトリ> はそのフォルダーの一覧を出す。
<!-- SECTION:DECISION:END -->

## Consequences

<!-- SECTION:CONSEQUENCES:BEGIN -->
<!-- SECTION:CONSEQUENCES:END -->

