---
id: TASK-163
title: 「ドット始まり = 隠しファイル」判定を単一情報源化し .skipsHiddenFiles との意味差を文書化する
status: To Do
assignee: []
created_date: '2026-07-27 05:49'
labels: []
dependencies: []
priority: medium
type: enhancement
ordinal: 238000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Quick Open で「ドット始まり = 隠し」の知識が3箇所に重複実装された:
- DirectoryFileScanner.swift:77 — name.hasPrefix(".")
- QuickOpenCandidates.swift:135-138 — relative.split(separator:"/").contains { $0.hasPrefix(".") }
- QuickOpenModel.swift:137,142 — fragment/name の hasPrefix(".")

一方、既存のサイドバー系（DirectoryLister.swift:107 / SupportedFileResolver.swift:19）は FileManager の .skipsHiddenFiles を使っており、こちらは chflags hidden（例: ~/Library）も隠す。つまり Quick Open とサイドバーで「隠しファイル」の定義が静かに割れている。

git 索引由来の候補は文字列しか無いためドット判定に寄せるのは合理的（走査と索引のフィルタが同一意味になる利点もある）が、その設計判断がどこにも書かれていない。BefoldKit に述語を1つ切り出して coding_rule.md の単一情報源テーブルへ登録し、3箇所とも委譲する。「.skipsHiddenFiles（Finder 隠しフラグ込み）をあえて使わない理由」を /// に書く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ドット始まり判定の実装が BefoldKit の述語1つに集約され、DirectoryFileScanner / QuickOpenCandidates / QuickOpenModel がそれに委譲している
- [ ] #2 「.skipsHiddenFiles を使わず文字列判定に寄せる理由」がドキュメンテーションコメントとして残る
- [ ] #3 coding_rule.md の単一情報源テーブルに述語が登録される
<!-- AC:END -->
