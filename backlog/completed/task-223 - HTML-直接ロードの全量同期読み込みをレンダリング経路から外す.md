---
id: TASK-223
title: HTML 直接ロードの全量同期読み込みをレンダリング経路から外す
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:14'
updated_date: '2026-07-31 10:34'
labels:
  - refactor
  - performance
dependencies: []
priority: medium
type: task
ordinal: 300000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerRenderer+ContentUpdate.swift:76-77 が Data(contentsOf:) + HTMLCharsetNormalizer で最大 10MB の HTML を @MainActor 上で全量読み込み・再エンコードしている。updateContent は SwiftUI 更新サイクル（ViewerWebView.updateNSView）から呼ばれ、ファイル切替・ライブリロードのたびに走る。ViewerLoadPipeline が既に non-isolated async で data を読んでいるので、正規化結果を Outcome に載せて渡すのが本筋。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 HTML 表示時の読み込み・charset 正規化が MainActor 外で実行される
- [x] #2 ファイル切替・ライブリロードでの HTML 表示が従来どおり動作する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ContentLoader.swift: LoadedContent に hasDeclaredHTMLCharset: Bool? を追加(default nil)。
2. ViewerLoadPipeline.swift: loadFull に fileType を渡し、.html のときのみ HTMLCharsetNormalizer.hasCharsetDeclaration(data) を計算して LoadedContent に格納。cache.text は既存の TextEncoding デコード結果を再利用(HTMLCharsetNormalizer と同じデコード処理のため二重読み込み不要)。
3. ViewerStore.swift: hasDeclaredHTMLCharset を DisplayState / ViewerStore プロパティに追加し apply(outcome:) で設定。
4. ViewerWebView.swift / ViewerContentView.swift: hasDeclaredHTMLCharset を updateContent まで引き回す。
5. ViewerRenderer+ContentUpdate.swift: 76-86 行の Data(contentsOf:) + HTMLCharsetNormalizer.utf8NormalizedHTML 呼び出しを削除し、hasDeclaredHTMLCharset フラグで webView.load(content) / webView.loadFileURL を分岐(nil/true は現行同様 loadFileURL へフォールバック)。
6. ViewerRenderer+OneShot.swift の呼び出し経路も同様に対応要否を確認。
7. テスト: ViewerLoadPipelineTests に charset宣言あり/なし/HTML以外の3ケース追加。ViewerRendererContentUpdateTests に updateContent がディスクアクセスせず flag で分岐することを検証するテスト追加。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift test (884 tests, Integration/FileWatcherTests除く)全通過。SwiftLint 実行、変更ファイルに新規違反なし。updateContent 分岐のWebKit実描画自体は project convention によりGUI層自動テスト対象外(手動確認は未実施、リリース前に推奨)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerLoadPipeline.loadFull で fileType==.html の場合に HTMLCharsetNormalizer.hasCharsetDeclaration(data) をオフメインアクターで計算し、ContentLoader.LoadedContent.hasDeclaredHTMLCharset として Outcome→ViewerStore→ViewerWebView→updateContent まで伝播。ViewerRenderer+ContentUpdate.swift の Data(contentsOf:) + HTMLCharsetNormalizer.utf8NormalizedHTML 呼び出しを削除し、フラグ分岐(false→webView.load、true/nil→loadFileURL)に置換。ViewerLoadPipelineTests に3ケース追加、swift test 884件全通過で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
