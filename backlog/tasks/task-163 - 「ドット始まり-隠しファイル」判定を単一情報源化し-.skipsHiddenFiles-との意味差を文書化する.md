---
id: TASK-163
title: 「ドット始まり = 隠しファイル」判定を単一情報源化し .skipsHiddenFiles との意味差を文書化する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-27 05:49'
updated_date: '2026-07-27 06:36'
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
- [x] #1 ドット始まり判定の実装が BefoldKit の述語1つに集約され、DirectoryFileScanner / QuickOpenCandidates / QuickOpenModel がそれに委譲している
- [x] #2 「.skipsHiddenFiles を使わず文字列判定に寄せる理由」がドキュメンテーションコメントとして残る
- [x] #3 coding_rule.md の単一情報源テーブルに述語が登録される
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
BefoldKit に HiddenFileRule(isHidden(component:) / containsHiddenComponent(inRelativePath:)) を新設し、DirectoryFileScanner:77 / QuickOpenCandidates.isHidden / QuickOpenModel.pathCandidates(fragment/name)の3箇所を委譲。.skipsHiddenFiles(chflags hidden も隠す)をあえて使わず文字列判定に寄せる理由を /// に記載。coding_rule.md の単一情報源テーブルへ登録。HiddenFileRuleTests 2本追加、既存の隠しファイル系テストも通過、swift test 全736パス、lint クリーン。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
「ドット始まり=隠し」判定が3箇所に重複していたのを BefoldKit.HiddenFileRule に集約し3箇所とも委譲。サイドバー系の .skipsHiddenFiles と定義が割れている件と、文字列判定に寄せる理由(git 索引由来候補は文字列のみで走査・索引のフィルタ意味を揃えるため)を /// と coding_rule.md 単一情報源テーブルに明文化。HiddenFileRuleTests で固定、全736パス。
<!-- SECTION:FINAL_SUMMARY:END -->
