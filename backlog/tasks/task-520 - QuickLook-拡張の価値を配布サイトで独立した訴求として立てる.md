---
id: TASK-520
title: QuickLook 拡張の価値を配布サイトで独立した訴求として立てる
status: To Do
assignee: []
created_date: '2026-08-18 14:54'
updated_date: '2026-08-21 07:53'
labels: []
milestone: m-1
dependencies:
  - TASK-518
priority: medium
type: enhancement
ordinal: 760000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldQuickLook/ の QuickLook 拡張により、befold をインストールすると Finder でスペースキーを押すだけで Markdown / Mermaid がレンダリング済みで読めるようになる。これは「アプリを開く」より摩擦の低い、多くの Mac ユーザーにとって最も日常的な入口だが、製品名からは想像できないため、現在のサイトでは機能一覧の 1 項目に埋もれている。

QuickLook 対応を独立した訴求ブロックとして立て、「インストールすると Finder のスペースキーが強くなる」という価値が一目で伝わるようにする。

前提と裏付け:
- コード参照: BefoldQuickLook/ が QuickLook 拡張（appex）として存在し、ViewerRenderer を直接使って 1 回描画する（.claude/CLAUDE.md のターゲット表）
- 未確認: 現在サイト上で QuickLook がどう言及されているかは着手時に site/src/views/shared.tsx の機能リストを読んで確認する。言及ゼロではないはずだが、独立した見出しにはなっていない

TASK-518 に依存する: この訴求は「スペースキーを押す → その場で描画される」という動きでしか伝わらず、静止画では成立しない。GIF/動画の素材が先に無いと、ブロックを作った後に素材を差し替える二度手間になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 配布サイトに QuickLook を主題とした独立の訴求ブロック（または節）がある
- [ ] #2 スペースキーを押してから描画されるまでの動きが、動く素材で示されている
- [ ] #3 機能一覧側の記述と重複せず、どちらを読んでも矛盾しない
- [ ] #4 日英どちらの言語でも表示できる
<!-- AC:END -->
