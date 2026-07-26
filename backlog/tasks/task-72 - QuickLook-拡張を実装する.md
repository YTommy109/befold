---
id: TASK-72
title: QuickLook 拡張を実装する
status: To Do
assignee:
  - '@tokutomi'
created_date: '2026-07-19 06:38'
updated_date: '2026-07-26 06:06'
labels: []
dependencies: []
ordinal: 210000
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
コード品質を新機能より優先する方針に伴い、本タスクを保留して To Do へ戻した（子タスク 7 件はすべて未着手で、実装成果物はない）。再開の目安: 構造リファクタ層（TASK-135 / 133 / 134 / 139 / 140 系 / 136 / 137 / 138）とテスト品質層が片付いた時点。

## 進捗と中断(2026-07-26)
子タスク 72.1 / 72.2 / 72.3 / 72.4 は Done。72.5 は実装完了・コミット済みだが
AC#1 未達のまま中断。72.6 / 72.7 は着手不可。

### 中断理由: 対象 UTI の多くが他の QuickLook 拡張に取られる
QuickLook は 1 つの UTI につき拡張を 1 つしか選ばず、優先度を指定する API はない。
実機(macOS 26.5.2)で qlmanage -p により appex の起動有無を確認した結果:
- 起動する: .mermaid / .swift / .json
- 起動しない(設計どおり対象外): .pdf
- 起動しない(想定外): .md / .markdown / .svg / .html / .csv

競合相手:
- markdown 系 UTI → org.sbarex.QLMarkdown.QLExtension (/Applications/QLMarkdown.app)
- public.html → com.apple.Safari.SafariQuickLookPreview
- public.svg-image → システム標準の画像プレビュー

befold 側のコードの不具合ではなく環境側の競合だが、この状態では
AC#1「.mmd/.mermaid, .md/.markdown, .svg, .html/.htm, .csv/.tsv を
レンダリングモードでプレビューできる」は競合アプリが入った環境では
原理的に満たせない。AC#1 の見直しが必要。

### 再開時に決めること
1. AC#1 の対象範囲を、実効性のある種別(mermaid + ソースコード系)へ縮小するか
2. 宣言は残したうえで「環境によっては選ばれない」と割り切り、
   競合をユーザーへ知らせる仕組みを別途用意するか
3. .svg の public.svg-image 宣言(TASK-72.4 で決めた判断)を維持するか

### 未実施
レンダリング結果そのものの目視確認(TASK-72.7 の手動チェック項目)。
<!-- SECTION:NOTES:END -->
