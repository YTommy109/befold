---
id: TASK-518
title: QuickLook で Mermaid 入り Markdown が描画される動きを見せる短尺 GIF/動画を用意しサイトと SNS で使う
status: Done
assignee: []
created_date: '2026-08-18 14:52'
updated_date: '2026-10-09 08:50'
labels: []
milestone: m-10
dependencies: []
priority: high
type: task
ordinal: 758000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状のサイトは静止スクリーンショット 8 枚のみで（site/public/images/screenshot-*.png）、befold の使い心地が動きとして伝わらない。10 秒前後の GIF（または mp4）を 1 本用意し、ランディングの主要導線と SNS 投稿の両方で使い回せる素材にする。

撮る場面: Finder で Mermaid 入りの .md を選び、スペースキーを押すと QuickLook でレンダリング済みの Markdown と図がその場で表示される流れ。

場面の選定理由（2026-09-27 に方針変更）: 当初は「保存すると即座に再描画される（自動リロード）」を撮る予定だったが、自動リロードは VS Code プレビュー・Typora・Marked 2 など多くの Markdown ツールが備える機能で、差別化にならない。ランディングの説明文（site/src/views/landing.tsx）でも特徴の 1 つとして並べているだけで、一番の売りとして扱っていない。一方で QuickLook での描画は他ツールと見分けがつく体験であり、TASK-520（QuickLook の訴求ブロック）が必要とする「スペースキー → その場で描画」の素材そのものでもあるため、1 本でその依存も満たせる。

背景: analytics 上 PV が少なく、必要とするユーザー（コーディングエージェントが生成した Markdown/Mermaid を読む Mac 開発者）へリーチできていない。

未確認の前提:
- 動画のほうが静止画より訴求力が高いという点は測定していない（analytics で確認できたのは PV が少ないことだけ）。
- 現在のランディングはカルーセル（site/public/carousel.js）で静止画を並べる構成のため、動画素材をどこに差し込むかは実装時に site/src/views/landing.tsx を読んで決める。TASK-520 の訴求ブロックへ置く案と、ヒーロー付近へ置く案がある。

注意: 撮影はスクリーンショットと同じく対話セッションでしか行えない（TCC の画面収録許可が背景ジョブに下りない）。外観はダークに固定して撮る。QuickLook 拡張がインストール済みの befold（/Applications 配下）で撮ること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Finder で Mermaid 入りの .md を選んでスペースキーを押し、QuickLook で描画されるまでの流れが分かる 10 秒前後の素材が site/public/images 配下に置かれている
- [x] #2 ランディングページで素材が再生され、静止画カルーセルと役割が重複していない
- [x] #3 ファイルサイズが本文の表示を阻害しない範囲に収まっており、実測値をタスクの Notes に記録している
- [x] #4 SNS 投稿へそのまま添付できる形式（GIF もしくは mp4）で書き出されている
- [x] #5 TASK-520 の QuickLook 訴求ブロックで同じ素材を流用できる（別撮りが不要な）構図・尺になっている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-09 撮影・書き出し済み。QuickLook 拡張入り befold（/Applications 配下、ダーク）で、無地の背景に Finder 窓 1 枚→.md を選択→スペースキー→Mermaid シーケンス図入りで描画、までを録画。実測: mp4 60.7KB / GIF 700KB / 960x698 / 8.2 秒（Finder 1.4 秒 + 表示アニメ + 結果 6 秒の保持）。配置: site/public/images/quicklook-demo.mp4（LP で使用）・quicklook-demo.gif（SNS 添付用。LP では未使用）・quicklook-demo-poster.png。撮影時に背景へ個人情報（ターミナル・Finder サイドバー）が写り込んだため、無地の覆い窓で隠して撮り直した。LP への配置は TASK-520 の QuickLook ブロックで行い、ローカルの wrangler dev で再生（paused=false・currentTime 進行）を確認済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
QuickLook でスペースキー→Mermaid 入り Markdown が描画される 8.2 秒の素材（mp4 61KB / GIF 700KB）を撮影し、LP の QuickLook ブロックで再生。
<!-- SECTION:FINAL_SUMMARY:END -->
