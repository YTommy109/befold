---
id: TASK-927
title: Mermaid 図の naturalHeight がラップ時の 1 回の実測に固定され、後の高さ変化に追従しない
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T11:24:00Z'
updated_date: '2026-11-09T12:12:00Z'
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
- [x] #1 フォントの遅延読み込みと非表示中のラップについて、枠が図より小さく残るかどうかの実測が Notes に記録されている
- [x] #2 再現した場合、すべての図の枠が図の高さに追従し、修正を戻すと落ちる回帰テストがある。再現しない場合、直さない根拠が Notes に記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 枠が図より小さく残る経路を実 WKWebView で測る（フォント、非表示、図の種類、リサイズ、全体ズーム）
2. 再現すれば ResizeObserver 等を検討し、再現しなければ根拠を Notes に残して直さない
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-926 の結果: 非表示中のラップのうち「古い文書のエラーで隠れた状態で包む」経路は解消した（実測で naturalHeight 697）。壊れた .mmd を単独で表示したときの naturalHeight 0 は、エラー表示中の正常な状態。残る主張はフォントの遅延読み込みなど、包んだ後の高さの変化。

実測（2026-11-09、4b71eeb1 のバンドル、実 WKWebView 1200x800、実 mermaid.min.js、各条件 3 回以上）。「枠が小さい」は .diagram-zoom-scroll の scrollHeight - clientHeight で判定。

再現せず。図が枠に隠れる状況はなかった。

- 図の種類: 19 種（flowchart / sequence / class / state / er / gantt / pie / journey / mindmap / timeline / quadrant / gitGraph / sankey / C4 / xychart / block / architecture / packet / requirement）で差は 0
- フォントの遅延読み込み: 経路が無い。style.css と viewer.html に @font-face が無く、viewer-src に FontFace も無い。擬似的に CSS で font-family を変えても差は 1px、font-size 30px でも 5px
- 実在するフォント変更: 等幅フォントは `_mmdInitCodeFont` で表示中に変わりうるが、Courier New + 40pt で差は 1px。本文の文字サイズは ViewerWebViewFactory.swift がビュー作成時に注入するだけで表示中には変わらない（実入口を直接呼んだ場合 20pt で 2px、40pt で 7px）
- 差が出ても図は隠れない: SVG の高さは変わらず（677px のまま）、枠は 680px のまま。増えるのは inner の高さだけで、図の下の余白の分と読める（余白の内訳は未測定）
- 非表示中のラップ: `#diagram-wrap` を隠す viewer-src の経路は _mmdMermaidParseError の .mmd だけ（rg で確認）。この場合はエラー表示中で図の枠は見えず、naturalHeight 0 は次の render で測り直す（TASK-926 の対照で 697）。WebView をウィンドウから外す / isHidden / 0x0 / 300x200 の状態で描画して戻しても、naturalHeight は通常と同じ 906 / 319
- ウィンドウのリサイズ: 400 / 1600px 幅で差は 0。枠の上限は resize で追従（20ms）
- 全体ズーム 200%: naturalHeight と実寸は一致。差が出るのは上限（ビューポート高）で切られる設計どおりの場合だけ。なお、200% のまま再描画すると flowchart の naturalHeight は 906 から 1122 に変わる（図の実寸も同じ値なので枠は正しい。mermaid のレイアウト自体が変わる理由は未調査）

ResizeObserver は入れない。追従すべき高さの変化が観測できず、仕組みだけが増えるため。TASK-925 の型の症状（枠 116 / 中身 639）は描画前に測ることが原因で、TASK-925 で解消済み。

未確認の外れ値: narrow-then-wide（300x200 で描画し 1200x800 へ）が初回 3 回のうち 1 回だけ、500ms 後も枠が上限の 136px のままだった。その後 15 回の再実行と、別手順の 12 回では再現せず（いずれも正常）。naturalHeight ではなく resize の経路で、原因は未特定。ハーネスの連続実行による可能性もある。

実アプリでは測っていない（単体ハーネス）。コードの変更なし、docs/dev の更新不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
枠が図より小さく残る問題は再現せず、コードは変更していない。実 WKWebView で、図 19 種、フォント変更、非表示や 0 サイズでの描画、リサイズ、全体ズームを測り、図が枠に隠れる状況はなかった。Web フォントの経路自体が無く、表示中に変わる等幅フォントの影響は 1px で、SVG は枠に収まる。追従すべき変化が無いので ResizeObserver は入れない。リサイズ後に枠が小さいまま残る外れ値が 1 回あったが、以後 27 回再現せず原因は未特定（Notes 参照）。
<!-- SECTION:FINAL_SUMMARY:END -->
