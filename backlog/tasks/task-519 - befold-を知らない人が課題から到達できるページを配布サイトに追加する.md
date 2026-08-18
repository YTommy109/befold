---
id: TASK-519
title: befold を知らない人が課題から到達できるページを配布サイトに追加する
status: To Do
assignee: []
created_date: '2026-08-18 14:53'
labels: []
dependencies: []
priority: medium
ordinal: 759000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状の配布サイト（site/src/views/landing.tsx・features.tsx）は「befold とは何か」を説明する構成で、製品名を既に知っている人しか到達できない。まだ誰も befold を知らないため、名前検索の流入はほぼ期待できない。

そこで、ユーザーが実際に抱えている課題の側から着地できるページを用意する。想定する課題の例:
- Mac の Finder でスペースキーを押しても Markdown が読めない（QuickLook が素の .md をプレビューできない）
- Mermaid の図をブラウザや Web サービスに貼らずにローカルで見たい
- Claude Code / Codex が生成した設計書・ADR をレビューしたいが、素の Markdown では読みにくい

各ページは課題の説明を主役にし、befold は解決手段の 1 つとして提示する。既存の機能一覧ページ（features.tsx）とは役割が異なるので、内容を重複させない。

前提と裏付け:
- コード参照: site/src/views/landing.tsx:71-76 でタイトル・meta description が製品名起点になっている
- コード参照: site/src/views/features.tsx:15-16 も同様に製品説明から始まる
- 未確認: 各課題に実際どれだけ検索需要があるかは測っていない。ページを出した後 site の analytics で流入を見て判断する

対象ページ数と具体的な題材は着手時に決める。まず 1 本作って流入を観測し、効果が確認できてから増やす方針でよい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 課題起点のページが配布サイトに 1 本以上追加され、landing / features とは別の URL で配信されている
- [ ] #2 ページのタイトルと meta description が製品名ではなく課題の記述から始まっている
- [ ] #3 既存の landing / features ページと内容が重複しておらず、相互のリンク導線がある
- [ ] #4 日英どちらの言語でも表示できる（既存ページと同じ多言語の仕組みに乗っている）
- [ ] #5 追加したページへの流入を後から分離して確認できる（analytics 上でページ別に集計できる）
<!-- AC:END -->
