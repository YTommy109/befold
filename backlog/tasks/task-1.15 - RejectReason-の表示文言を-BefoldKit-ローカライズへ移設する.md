---
id: TASK-1.15
title: RejectReason の表示文言を BefoldKit ローカライズへ移設する
status: To Do
assignee: []
created_date: '2026-07-19 02:56'
labels: []
dependencies: []
parent_task_id: TASK-1
priority: high
type: enhancement
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイズ超過・非対応ファイル時のユーザー向け表示が befold/Viewer/UnsupportedFileView.swift と app 側ローカライズ（befold/App/LocalizedBundle.swift、xcodebuild では Bundle.main）に依存しており、QuickLook 拡張からプレースホルダ表示に再利用できない。RejectReason のユーザー向け文言を BefoldKit 側の Localizable リソースへ移し、appex からもアクセスできるようにする。TASK-1.2（viewer.js 注入文字列の移設）と同方針の続きで、対象はネイティブ表示側の文言。2026-07-19 のアーキテクチャレビューで特定。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 RejectReason のユーザー向け文言が BefoldKit のリソースバンドルから取得できる
- [ ] #2 アプリ本体の表示（UnsupportedFileView）は挙動不変
- [ ] #3 日英の翻訳漏れがない（l10n チェック通過）
<!-- AC:END -->
