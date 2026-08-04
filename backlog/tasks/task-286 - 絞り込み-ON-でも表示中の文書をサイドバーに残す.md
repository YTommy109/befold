---
id: TASK-286
title: 絞り込み ON でも表示中の文書をサイドバーに残す
status: To Do
assignee: []
created_date: '2026-08-04 07:28'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 489000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)。SidebarNavigator.ensureCurrentFile(in:) は『開いている文書がサイドバーから消える回帰』を防ぐために entries へ必ず含める不変条件だが、TASK-264 の絞り込みは visibleEntries 側で効くためこの不変条件を迂回する。

再現: 他に変更ファイルがあるリポジトリで、コミット済み・未変更の文書（例 README.md）を開いた状態で ⌘⌃G を押すと、その行が一覧から消え選択ハイライトも失われる。コンテンツ側は表示し続けるため、矢印キーの移動が一覧に無いエントリ基準になる。

検討事項: filterText 側は『ユーザーが自分で打った絞り込み』なので消えても納得できるが、git 絞り込みは状態由来で消えるため同じ扱いでよいかは判断が要る。visibleEntries に例外を足すのか、ensureCurrentFile 相当を絞り込み後にも通すのかで置き場所が変わる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 絞り込み ON で未変更の文書を開いていても、その行がサイドバーに残る
- [ ] #2 残した行の選択ハイライトと矢印キー移動が一覧と整合する
- [ ] #3 filterText による絞り込みとの扱いの違い（残す/残さない）が決められ、理由が記録される
- [ ] #4 回帰テストがあり、修正を戻すと落ちることを確認する
<!-- AC:END -->
