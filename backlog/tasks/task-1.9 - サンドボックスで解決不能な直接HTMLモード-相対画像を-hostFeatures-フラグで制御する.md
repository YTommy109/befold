---
id: TASK-1.9
title: サンドボックスで解決不能な直接HTMLモード/相対画像を hostFeatures フラグで制御する
status: To Do
assignee: []
created_date: '2026-07-18 13:41'
updated_date: '2026-07-18 13:41'
labels: []
dependencies:
  - TASK-1.1
parent_task_id: TASK-1
priority: high
type: enhancement
ordinal: 6130
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
アーキテクチャ／セキュリティレビュー（2026-07-18）で発見（必須・要方針決定）。QuickLook 拡張（.appex）は App Sandbox 下で対象ファイル単体の read しか持たず親ディレクトリ権限がない。現行は (1) 直接 HTML モードで loadFileURL(filePath, allowingReadAccessTo: filePath.deletingLastPathComponent())（ViewerWebView.swift:351）が親ディレクトリ read を要求、(2) renderableContent→MarkdownImageEmbedder.embedLocalImages(baseURL: filePath)（ViewerWebView.swift:535-540）が兄弟ファイル（相対画像）を読む。いずれも appex でサンドボックス違反/ブロックになる。加えて直接 HTML は viewer.html を経由せず CSP 非適用で外部サブリソース（<img src=https://…>）を遮断できない（受動的トラッキング）。方針: hostFeatures と同型のフラグ（allowDirectHTML/embedImages）を注入経路に追加し、QuickLook では直接 HTML モード無効化・相対画像は解決不能を許容・read スコープをファイル単体に縮小する。task-1.1 の抽出ドライバに注入点を設ける。QuickLook 前に必須。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 allowDirectHTML/embedImages 相当の hostFeatures フラグで直接HTMLモードと相対画像埋め込みを無効化できる
- [ ] #2 フラグ無効時に親ディレクトリ/兄弟ファイルへのアクセスが発生しない
- [ ] #3 アプリ本体では従来どおり直接HTML表示・相対画像埋め込みが動作する
<!-- AC:END -->
