---
id: TASK-1
title: QuickLook 対応の事前リファクタリング
status: To Do
assignee: []
created_date: '2026-07-16 00:38'
updated_date: '2026-07-18 14:52'
labels: []
dependencies:
  - TASK-11
  - TASK-17
  - TASK-13
  - TASK-15
  - TASK-14
  - TASK-12
  - TASK-16
  - TASK-9
  - TASK-8
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QuickLook Preview Extension（.appex）でレンダリングコアを再利用するための事前リファクタリング群。GitHub Issues #209〜#214 から移行。

2026-07-18 にアーキテクチャ／セキュリティ／パフォーマンスの3観点でコードレビューを実施し、QuickLook 前の必須事項を再確認して本計画を更新した。

【完了済み】
- 1.2 ローカライズ文字列を BefoldKit へ移設
- 1.3 postMessage を _mmdPostMessage に一本化・hostFeatures 導入
- 1.4 ViewerLoadPipeline を監視/永続化から分離
- 1.6 小さな重複・整合の解消

【QuickLook 前に必須】
- 1.1 レンダリングコア（WKWebView ドライバ）を新設 BefoldRenderKit へ抽出
- 1.7 markdown-it の HTML サニタイザ XSS（DOMPurify 導入）
- 1.8 NormalizedTextCache の全量 materialize を先頭打ち切り読込にする（appex メモリ上限対策）
- 1.9 サンドボックスで解決不能な直接HTMLモード/相対画像埋め込みを hostFeatures フラグで制御

【推奨（必須と同時が望ましい）】
- 1.10 mermaid.min.js（3.2MB）の遅延ロード
- 1.11 QuickLook 経路で SHA256 全量ハッシュ・エンコーディング全量再スキャンをスキップ
- 1.12 多層防御（referenceActivated/loadMoreLines のゲート・CSP から unsafe-inline 削除）

【QuickLook の前提ではない（後回し可）】
- 1.5 ViewerWindowController 減量（appex はウィンドウを持たず不使用。アプリ内部品質として独立に扱う）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 レンダリングコアが QuickLook 拡張から再利用可能なターゲット(BefoldRenderKit)に抽出されている
- [x] #2 ローカライズ文字列が QuickLook 拡張からアクセスできる
- [x] #3 postMessage がガード付きヘルパーに一本化されている
- [x] #4 読込パイプラインが watcher/永続化から分離されている
- [x] #5 markdown-it の HTML サニタイズが DOMPurify で堅牢化され XSS バイパスが塞がれている
- [ ] #6 巨大ファイルを先頭チャンクだけで打ち切りメモリを抑える読込経路がある
- [ ] #7 サンドボックスで解決不能な直接HTML/相対画像が hostFeatures フラグで制御される
- [x] #8 小さな重複・整合課題が解消されている
<!-- AC:END -->
