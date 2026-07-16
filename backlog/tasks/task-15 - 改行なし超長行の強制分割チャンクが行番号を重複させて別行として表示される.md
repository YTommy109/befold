---
id: TASK-15
title: 改行なし超長行の強制分割チャンクが行番号を重複させて別行として表示される
status: Done
assignee: []
created_date: '2026-07-16 00:54'
updated_date: '2026-07-16 04:25'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/196'
priority: high
type: bug
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
改行を含まない 1MB 超の 1 行（minified JS など）は LineChunkReader が強制分割するが、JS 側 appendChunk は継続チャンクを前行のセルへ結合せず常に新しい <tr> を追加するため、同じ行番号が繰り返される。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 _lastChunkEndedWithNewline === false の場合、最初の行分が既存最終行に結合される
- [x] #2 行番号が重複しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
appendChunk(viewer.html) は buildLineNumberRows の出力を常に新規 <tr> として追記していたため、強制分割の継続行でも既存最終行と同じ行番号を持つ別行が生成されていた。修正方針: 生成した行 HTML を一時 tbody にパースし、_lastChunkEndedWithNewline===false のとき先頭行のセル内容だけを既存最終行の line-content セルへ insertAdjacentHTML で結合し、先頭 <tr> は破棄して残りだけを追記する。加えて render() が _lastChunkEndedWithNewline を常に true にリセットしていたため、初回チャンク自体が改行なしで終わる強制分割の1回目でも判定を誤っていた点も同一原因として修正(appendChunk と同じ末尾判定式に統一)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift scripts/webview-smoke.swift の appendChunk 呼び出しシナリオで手動検証: (1) 改行なし超長行の強制分割で継続チャンクが既存最終行セルへ結合され、行番号が重複しないことを確認 (2) 通常の改行区切りチャンクでは従来どおり別行として追加されることを確認(回帰なし)。npx jest 174件全通過、既存 webview-smoke.swift 全通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
appendChunk(BefoldApp/BefoldKit/Resources/viewer.html) を修正し、_lastChunkEndedWithNewline===false の強制分割継続チャンクでは生成した先頭行のセル内容だけを既存最終行の line-content セルへ結合し、新規 <tr> を追加しないようにした。加えて render() が _lastChunkEndedWithNewline を無条件 true にリセットしていたため初回チャンク自体が改行なしで終わる1回目の強制分割を誤検知していたバグも同一原因として修正。検証: npx jest 174件全通過、scripts/webview-smoke.swift 全通過、加えて WKWebView 経由の一時検証スクリプトで appendChunk を直接呼び出し (1) 継続チャンクが既存最終行へ結合され行番号が重複しないこと (2) 改行区切りの通常チャンクは従来どおり別行になり回帰がないこと、をそれぞれ確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
