---
id: TASK-518
title: 自動リロードの動きを見せる短尺 GIF/動画を用意しサイトと SNS で使う
status: To Do
assignee: []
created_date: '2026-08-18 14:52'
updated_date: '2026-08-21 07:53'
labels: []
milestone: m-10
dependencies: []
priority: high
type: task
ordinal: 758000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状のサイトは静止スクリーンショット 8 枚のみで（site/public/images/screenshot-*.png）、befold の中核価値である「ファイルを保存すると即座に再描画される」体験が伝わらない。10 秒前後の GIF（または mp4）を 1 本用意し、ランディングの主要導線と SNS 投稿の両方で使い回せる素材にする。

背景: analytics 上 PV が少なく、必要とするユーザー（コーディングエージェントが生成した Markdown/Mermaid を読む Mac 開発者）へリーチできていない。静止画より動作の実演のほうが 1 素材あたりの訴求力が高く、X / Zenn / Reddit いずれの面でもそのまま使える。

未確認の前提: 現在のランディングがカルーセル（site/public/carousel.js）で静止画を並べている構成のため、動画素材をどこに差し込むかは実装時に site/src/views/landing.tsx を読んで決める。

注意: 撮影はスクリーンショット同様に対話セッションでしか回せない（TCC の画面収録許可が背景ジョブに下りない）。外観はダーク固定で撮る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 保存 → 自動リロードの流れが分かる 10 秒前後の素材が site/public/images 配下に置かれている
- [ ] #2 ランディングページで素材が再生され、静止画カルーセルと役割が重複していない
- [ ] #3 ファイルサイズが本文の表示を阻害しない範囲に収まっており、実測値をタスクの Notes に記録している
- [ ] #4 SNS 投稿へそのまま添付できる形式（GIF もしくは mp4）で書き出されている
<!-- AC:END -->
