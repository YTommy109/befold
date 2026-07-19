---
id: TASK-72
title: QuickLook 拡張を実装する
status: In Progress
assignee:
  - '@tokutomi'
created_date: '2026-07-19 06:38'
updated_date: '2026-07-19 06:43'
labels: []
dependencies: []
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold にファイル種別に応じたプレビューを提供する QuickLook Extension (appex) を追加する。TASK-1 系の事前リファクタリング（BefoldRenderKit 抽出・hostFeatures フラグ・XSS対策・NormalizedTextCache 先頭打ち切り等）は完了済みで、これを土台に本体実装を行う。対象ファイル種別は FileType.swift の分類を踏襲しつつ、PDF・画像（.pdf, .png/.jpg/.jpeg/.gif/.webp/.bmp/.ico）は macOS 標準の QuickLook が既に高品質なプレビューを提供するため、befold の QuickLook 拡張の対象から除外する。befold 拡張の対象は「レンダリングモード」の .mmd/.mermaid, .md/.markdown, .svg, .html/.htm, .csv/.tsv と、シンタックスハイライト対象の約40種のソースコード拡張子（FileType.codeExtensionLanguages）とする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 QuickLook Extension が .mmd/.mermaid, .md/.markdown, .svg, .html/.htm, .csv/.tsv をレンダリングモードでプレビューできる
- [ ] #2 QuickLook Extension が FileType.codeExtensionLanguages に含まれる拡張子をシンタックスハイライト付きでプレビューできる
- [ ] #3 PDF・画像拡張子（pdf/png/jpg/jpeg/gif/webp/bmp/ico）は befold の QuickLook Extension の対象外とし、Info.plist の対応 UTI/拡張子リストに含めない
- [ ] #4 拡張子と処理経路（レンダリング/ハイライト/対象外）の対応が FileType.swift のロジックと一致していることをテストで検証する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 描画完了検知とappexバンドルリソース解決をプロトタイプで検証(ViewerRendererへのonRenderComplete相当コールバック追加を含む)
2. FileType.swiftにQuickLook対象拡張子集合を返す純粋関数(quickLookSupportedExtensions)を追加し、レンダリング5種+codeExtensionLanguagesのみを対象、PDF/画像を除外
3. RendererFeaturesにQuickLook専用の全機能無効プリセット(quickLookRestricted)を追加
4. project.ymlにapp-extensionターゲットを追加し、Info.plist(QLSupportedContentTypes)・entitlements(サンドボックス有効・ネットワークなし)を新設。.svgはpublic.xml側に紐づけて画像UTIとの重複を避ける
5. QLPreviewingController(View-based)を実装し、loadOneShotの呼び出しのみの薄いラッパーとする
6. 大きめのmermaid/markdown/巨大コードファイルでappexのメモリ・起動速度を実機検証
7. FileType拡張子集合のユニットテスト、xcodebuildでのappexビルド確認、Finder上でのQuickLook手動検証(PDF/画像が対象外であることを含む)

各ステップをTASK-72の子タスクとして分割し、順に着手する。
<!-- SECTION:PLAN:END -->
