---
id: TASK-609
title: XSLT 変換表示のサイズ上限を XML 専用に分ける
status: Done
assignee: []
created_date: '2026-09-09 10:33'
updated_date: '2026-09-09 10:36'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 889000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-608 で XSL を伴う XML を全量読み込みへ切り替えた際、上限を非行指向テキストと共有の nonChunkableSizeLimit（本体 10MB / QuickLook 2MB）にした。e-Gov 一括ダウンロードの実データ 1,124 件のうち 1 件（国家公務員法 16.99MB）がこれを超え、XSLT 変換に載らずソースのチャンク表示（「1000 行を表示中」）になる。

10MB は mermaid / markdown / SVG / HTML と共有の値で、そちらは実測が桁違い（TASK-72.6: 非行指向 1MB で WebContent 901MB、4MB で 2.24GB）。一方 XSLT 変換後は素の HTML で描画エンジンを通らない。実測（WKWebView / macOS 26.5.2、viewer と同じ経路 = DOMParser→XSLTProcessor→innerHTML→サニタイズ相当→挿入）: 1.8MB→0.37s、5.4MB→1.05s / WebContent 221MB、17.0MB→1.53s / 686MB。

共有の 10MB は動かさず、XSLT 変換に載る XML だけ 20MB の別上限にする。QuickLook は appex のメモリを守るため 2MB 据え置き。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 XSLT 変換に載る XML の全量読み込み上限が本体で 20MB になり、10MB 超 20MB 未満の法令XMLが整形表示される
- [x] #2 md / mmd / svg / html の 10MB と QuickLook の 2MB は変わらない
- [x] #3 20MB を超える XML は従来どおりソースのチャンク表示へ落ち、fileTooLarge の空表示にはならない
- [x] #4 上記を担保するユニットテストがあり、修正を戻すと落ちることを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（WKWebView / macOS 26.5.2、viewer と同じ経路: DOMParser→XSLTProcessor→innerHTML→サニタイズ相当→挿入+レイアウト、e-Gov 法令XML）:
43KB→31ms / 0.70MB→160ms / 1.8MB→365ms / 5.4MB→1.05s・WebContent 221MB / 17.0MB→1.53s・WebContent 686MB。
サニタイズだけは DOMPurify がバンドル内でグローバルに出ていないため HTML 再パースで代用（実際は 3〜5 倍、17MB で +0.2s 程度）。

上限 20MB の根拠は、手元の e-Gov 一括ダウンロード 1,124 件（合計 475MB / 平均 413KB）の最大が 16.99MB（国家公務員法）だったこと。>10MB は 1 件（0.09%）、>2MB は 57 件（5.1%）。
共有の 10MB を動かさなかったのは TASK-72.6 の実測（非行指向 1MB→WebContent 901MB、4MB→2.24GB）が mermaid 描画由来で、XSLT 出力の素の HTML とは桁が違うため。

実装: ContentLoader.maxXMLTransformSizeBytes（20MB）と ViewerLoadPipeline.fullLoadSizeLimit(fileType:oneShotLoad:) を追加し、needsWholeDocument と loadFull の両方がそれを見る（片方だけだと fileTooLarge の空表示になる）。
テストは type_body_length を超えたため ViewerLoadPipelineXMLTests へ分割（xcodegen generate 済み）。修正を戻すと新規 2 件が落ちることを確認。swiftlint は main とのベースライン差分ゼロ（残る 1 件は main 由来の no_space_in_method_call）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
XSLT 変換に載る XML だけ全量読み込みの上限を 20MB に分離した（共有の 10MB と QuickLook の 2MB は据え置き）。16.99MB の国家公務員法が「1000 行を表示中」のソース表示に落ちていたのが整形表示になる。swift test（ViewerLoadPipeline 16 件）パス、実機で該当ファイルを開いて確認。
<!-- SECTION:FINAL_SUMMARY:END -->
