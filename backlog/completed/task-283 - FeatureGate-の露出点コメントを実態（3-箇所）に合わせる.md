---
id: TASK-283
title: FeatureGate の露出点コメントを実態（3 箇所）に合わせる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 06:46'
updated_date: '2026-08-04 06:54'
labels: []
dependencies: []
priority: low
ordinal: 473000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWindowController.swift:9-10 の 'フィーチャーゲートの判定はこの 1 箇所だけ' というコメントは、TASK-264 / TASK-282 で露出点が 3 箇所（makeSidebarGitStatusLoader / makeChangedFilesOnlyToggle / MainMenuBuilder のメニュー項目）に増えたため実態と合わなくなった。

また、このコメントは git 実行全般がゲート下にあるかのように読めるが、実際にゲートされているのは git ステータス系のみで、git rev-parse（基準ディレクトリ解決）・git ls-files（Quick Open）・git worktree list（WorktreeCatalog）・最近使ったリポジトリは stable でも常時稼働する（2026-08-04 に実測）。これらは公開済み機能であり、ゲートを足すべきという指摘ではない。コメントが誤読を招く点だけを直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 露出点が 3 箇所であることと、それぞれの場所がコメントから辿れる
- [x] #2 ゲート対象が git ステータス系に限られ、git 実行全般ではないことがコメントから読み取れる
- [x] #3 TASK-187（ゲート解除）で消すべき箇所が漏れなく分かる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
露出点の一覧は FeatureGate の宣言コメント 1 箇所に集約し、ViewerWindowController 側は「ここを含めて 3 箇所、一覧は FeatureGate にある」と参照する形にした（同じ列挙を 3 箇所に書くと必ずずれるため）。ゲート対象が git ステータス系に限られること、基準ディレクトリ表示・Quick Open・最近使ったリポジトリ・WorktreeCatalog は公開済みで stable でも git を動かすことも明記した。検証: swift build 成功、swiftformat 0 件（コメントのみの変更）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FeatureGate の宣言コメントに露出点 3 箇所（git status ローダー / ヘッダーボタン / View メニュー項目）の一覧と、ゲート対象が git ステータス系に限られる旨を記載し、ViewerWindowController の「判定はこの 1 箇所だけ」という記述をその参照へ書き換えた。コメントのみの変更で swift build と swiftformat で確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
