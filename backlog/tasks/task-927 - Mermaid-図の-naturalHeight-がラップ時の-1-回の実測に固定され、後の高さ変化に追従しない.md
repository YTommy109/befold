---
id: TASK-927
title: Mermaid 図の naturalHeight がラップ時の 1 回の実測に固定され、後の高さ変化に追従しない
status: To Do
assignee: []
created_date: '2026-11-09T11:24:00Z'
updated_date: '2026-11-09T11:47:00Z'
labels:
  - bug
  - viewer
dependencies:
  - TASK-926
references:
  - BefoldApp/viewer-src/zoom.ts
priority: low
type: bug
ordinal: 892000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`/code-review high` の指摘で、コードを読んだだけの未検証の主張。TASK-925 は測る時機だけを直し、`_mmdWrapDiagrams` が 1 回だけ測る構造は残っている（zoom.ts で確認済み）。

未検証の主張: 非表示の `#diagram-wrap` の中で包むと 0 が記録される。包んだ後に図の高さが変わると（フォントの遅延読み込みなど）古い値が残る。どちらも TASK-925 と同じく図が枠内スクロールの向こうに隠れる。

指摘の案は図の `ResizeObserver` で現在の倍率を割り戻すもの。TASK-925 は測り直しを「zoom 適用後の実測になる」として不採用にしたが、この案はその理由に答えている。ただし仕組みは増える。実害が測れなければ見送ってよい。非表示の経路は前提タスクの修正で消える可能性があるので、その後に測る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 フォントの遅延読み込みと非表示中のラップについて、枠が図より小さく残るかどうかの実測が Notes に記録されている
- [ ] #2 再現した場合、すべての図の枠が図の高さに追従し、修正を戻すと落ちる回帰テストがある。再現しない場合、直さない根拠が Notes に記録されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-926 の結果: 非表示中のラップのうち「古い文書のエラーで隠れた状態で包む」経路は解消した（実測で naturalHeight 697）。壊れた .mmd を単独で表示したときの naturalHeight 0 は、エラー表示中の正常な状態。残る主張はフォントの遅延読み込みなど、包んだ後の高さの変化。
<!-- SECTION:NOTES:END -->
