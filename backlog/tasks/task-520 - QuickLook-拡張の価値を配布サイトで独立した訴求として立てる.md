---
id: TASK-520
title: QuickLook 拡張の価値を配布サイトで独立した訴求として立てる
status: Done
assignee: []
created_date: '2026-08-18 14:54'
updated_date: '2026-10-09 08:50'
labels: []
milestone: m-12
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
- [x] #1 配布サイトに QuickLook を主題とした独立の訴求ブロック（または節）がある
- [x] #2 スペースキーを押してから描画されるまでの動きが、動く素材で示されている
- [x] #3 機能一覧側の記述と重複せず、どちらを読んでも矛盾しない
- [x] #4 日英どちらの言語でも表示できる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-09 着手不可: 依存先 TASK-518（QuickLook 描画の GIF/動画）が To Do。素材の撮影は対話セッションでしか行えない（TCC の画面収録許可が背景ジョブに下りない）ため、TASK-518 の素材が site/public/images 配下に置かれれば着手できる。AC#2 は素材が前提で、先にブロックだけ作ると差し替えの二度手間になる。現状サイトの QuickLook 言及は landing.tsx:107/118（一文）・features.tsx:156（FAQ）・shared.tsx:158（機能一覧 1 項目）の 3 箇所で、着手時に重複しない配置へ整理する。

2026-10-09 実装: landing.tsx に QuickLook 独立ブロック（日英）を追加、mp4 を autoplay/loop/muted で再生。reduced-motion では public/quicklook-demo.js が停止し controls を出す。冒頭文の「Quick Look にも対応してます」は二重訴求になるため削除。機能一覧（shared.tsx）と FAQ（features.tsx）は 1 行の事実のみで、ブロックと矛盾しない。検証: vitest（public-routes 52 件通過。新規テストで日英のブロックと動画 src を確認）、lint/format/tsc 通過、wrangler dev + Chrome で再生を確認。全体 vitest では public-pages-hosts の /releases 系 2〜4 件がタイムアウトするが、外部 appcast 取得の経路で本変更と無関係（単体再実行でも同じ 2 件）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LP に QuickLook の独立訴求ブロック（日英）を追加し、TASK-518 の実撮影素材（mp4）を再生。重複していた冒頭の一文を削除。vitest・lint・実ブラウザ再生で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
