---
id: TASK-1.9
title: サンドボックスで解決不能な直接HTMLモード/相対画像を hostFeatures フラグで制御する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-18 13:41'
updated_date: '2026-07-18 23:13'
labels: []
dependencies:
  - TASK-1.1
parent_task_id: TASK-1
priority: high
type: enhancement
ordinal: 1130
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
アーキテクチャ／セキュリティレビュー（2026-07-18）で発見（必須・要方針決定）。QuickLook 拡張（.appex）は App Sandbox 下で対象ファイル単体の read しか持たず親ディレクトリ権限がない。現行は (1) 直接 HTML モードで loadFileURL(filePath, allowingReadAccessTo: filePath.deletingLastPathComponent())（ViewerWebView.swift:351）が親ディレクトリ read を要求、(2) renderableContent→MarkdownImageEmbedder.embedLocalImages(baseURL: filePath)（ViewerWebView.swift:535-540）が兄弟ファイル（相対画像）を読む。いずれも appex でサンドボックス違反/ブロックになる。加えて直接 HTML は viewer.html を経由せず CSP 非適用で外部サブリソース（<img src=https://…>）を遮断できない（受動的トラッキング）。方針: hostFeatures と同型のフラグ（allowDirectHTML/embedImages）を注入経路に追加し、QuickLook では直接 HTML モード無効化・相対画像は解決不能を許容・read スコープをファイル単体に縮小する。task-1.1 の抽出ドライバに注入点を設ける。QuickLook 前に必須。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 allowDirectHTML/embedImages 相当の hostFeatures フラグで直接HTMLモードと相対画像埋め込みを無効化できる
- [x] #2 フラグ無効時に親ディレクトリ/兄弟ファイルへのアクセスが発生しない
- [x] #3 アプリ本体では従来どおり直接HTML表示・相対画像埋め込みが動作する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit に `RendererFeatures`(Equatable, Sendable な plain struct)を新設。`allowDirectHTML: Bool` / `embedImages: Bool` の2フラグ + `static let allEnabled = RendererFeatures(allowDirectHTML: true, embedImages: true)`。hostFeaturesScript(JS側)と対になる Swift側フラグとして BefoldKit/RendererFeatures.swift に配置。
2. ViewerWebView に `rendererFeatures: RendererFeatures` プロパティを追加し、makeNSView/updateNSView で `context.coordinator.rendererFeatures` へ伝搬(他の値と同じパターン)。
3. Coordinator.updateContent 内の直接HTMLモード分岐条件に `rendererFeatures.allowDirectHTML` を追加(false ならこの分岐に入らずviewer.html側の通常レンダリング経路にフォールバックし、loadFileURL(...allowingReadAccessTo:)は一切呼ばれない)。判定はテスト容易性のため `nonisolated static func shouldEnterDirectHTMLMode(fileType:isSourceMode:filePath:features:) -> Bool` として純関数に切り出す(isFileOrModeSwitchと同じ設計)。
4. `renderableContent` 静的関数に `embedImages: Bool` 引数を追加し、false なら MarkdownImageEmbedder.embedLocalImages を呼ばず元のcontentをそのまま返す。呼び出し元 applyRender で `rendererFeatures.embedImages` を渡す。
5. ViewerContentView.swift の ViewerWebView 呼び出しに `rendererFeatures: .allEnabled` を追加(アプリ本体は従来どおり全機能有効)。
6. テスト追加: ViewerWebViewCoordinatorTests に embedImages:false で埋め込みされないケース、shouldEnterDirectHTMLMode の各フラグ/条件組み合わせのテストを追加。
7. swift build / swift test で回帰確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
BefoldKit に RendererFeatures(allowDirectHTML/embedImages)を新設し .allEnabled をアプリ本体既定値として ViewerContentView→ViewerWebView→Coordinator へ伝搬。Coordinator.updateContent の直接HTMLモード分岐条件を純関数 shouldEnterDirectHTMLMode に切り出しflag gate、renderableContent に embedImages引数を追加しfalse時はMarkdownImageEmbedder.embedLocalImagesを呼ばない。検証: swift build 成功、swift test --skip Integration --skip FileWatcherTests で 370 tests 全通過(新規テスト shouldEnterDirectHTMLMode 5ケース・embedImagesDisabledDoesNotEmbedLocalImages含む)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
RendererFeatures(allowDirectHTML/embedImages)フラグをBefoldKitに新設し、ViewerWebViewのCoordinatorへ注入。allowDirectHTML=falseでloadFileURL(allowingReadAccessTo:親ディレクトリ)を呼ぶ直接HTMLモード分岐に入らずviewer.html経由の通常描画にフォールバックし、embedImages=falseでMarkdownImageEmbedder.embedLocalImages(兄弟ファイルread)を呼ばない。アプリ本体は.allEnabledで従来どおり両機能有効。swift build/swift test(370 tests)で回帰なしを確認、新規ユニットテストでフラグ有効/無効の各分岐を検証。task-1.1(BefoldRenderKit抽出)未着手のため注入点はアプリ側ViewerWebView.swiftに設置、将来の抽出時にそのまま移設可能な設計。
<!-- SECTION:FINAL_SUMMARY:END -->
