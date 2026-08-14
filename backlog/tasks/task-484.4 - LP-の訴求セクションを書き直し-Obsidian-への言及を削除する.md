---
id: TASK-484.4
title: LP の訴求セクションを書き直し Obsidian への言及を削除する
status: To Do
assignee: []
created_date: '2026-08-14 13:06'
updated_date: '2026-08-14 13:22'
labels: []
milestone: m-1
dependencies:
  - TASK-484.3
parent_task_id: TASK-484
priority: high
type: feature
ordinal: 709000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
トップページ（`site/src/views/landing.tsx`）の訴求部分を、ふたつの読み手を同格に扱う構成へ書き直す。

**現状**（landing.tsx:128-174）は 2 つの philosophy セクションが並ぶ。

1. 「Claude が設計する。私は befold でレビューする。」— AI が生成した Markdown をレビューするというエンジニア向けの訴求。これは残す方向で扱う
2. 「vault に登録しなくていい。」— Obsidian を引き合いに出し、worktree を vault へ登録せずその場で読めることを訴求。**Obsidian への言及はこのセクションの日本語版（:155）と英語版（:166）の 2 箇所が全て**

Obsidian への言及は削除する。ただしこのセクションが担っていた「登録も設定もなく、その場のフォルダをすぐ読める」という訴求自体には価値があるため、**言及を消してセクションごと落とすのか、固有名詞なしで書き直すのかをこのタスクで決める**。

そのうえで、TASK-484.3 で整理した「Markdown を読む立場の人にとっての利点」を、エンジニア向けの訴求と同じ重みで並べる。どちらか一方が主で他方が従、という見え方にしないこと。

hero のコピー（「Markdown を行き来する。快適に。」/「数百のファイルを抱えたリポジトリのための、Mac 専用の軽量ビューア」）が、ふたつの読み手を同時に受け止められているかもあわせて見直す。「リポジトリ」という言葉が非エンジニアの入口として働くかは論点。

日英は 1 つの HTML に両方を埋め込み `lang` 属性で出し分ける構造のため、両方を同時に書き直すこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Obsidian への言及がサイトのソースから完全に無くなっている
- [ ] #2 エンジニア向けの訴求と Markdown を読む立場の人向けの訴求が、同格に並んでいる
- [ ] #3 hero のコピーがふたつの読み手のどちらも排除していない
- [ ] #4 日本語と英語が同じ内容で書き直されている
- [ ] #5 /features ページの導入文が LP の訴求と食い違っていない
<!-- AC:END -->
