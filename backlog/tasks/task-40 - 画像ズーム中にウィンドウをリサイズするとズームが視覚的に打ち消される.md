---
id: TASK-40
title: 画像ズーム中にウィンドウをリサイズするとズームが視覚的に打ち消される
status: Done
assignee:
  - '@claude'
created_date: '2026-07-17 02:07'
updated_date: '2026-07-17 03:54'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
viewer.html の _mmdFitImage(:315) は wrap.clientWidth/clientHeight を #diagram-wrap から取得するが、この要素自体に CSS zoom が適用されている(viewer.html:93 `wrap.style.zoom = effectiveZoom(_mmdZoom)`)。zoom=z のとき clientWidth はローカル座標系で viewport/z を返すため、リサイズハンドラ(:322-329)経由の再フィットで画像が viewport/z ローカルpx にフィットされ、レンダリング結果はちょうどビューポートサイズ = ズームが視覚的に打ち消される(_mmdZoom は z のまま)。永続化されたズームが img.onload 前に適用される初回表示でも同様。

修正方向: フィット計算の基準を zoom 非適用の親要素(.viewer)の寸法にする、または diagramScrollHeight(viewer.js:79)と同様に globalZoom で補正する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ラスター画像をズーム(≠1)した状態でウィンドウをリサイズしてもズーム倍率が維持される
- [x] #2 永続化ズームがある状態での初回表示がフィット×ズームの設計(viewer.html の記述どおり)で描画される
- [x] #3 ズーム=1 でのウィンドウフィット挙動(TASK-19 の修正)は維持される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. _mmdFitImage の availWidth/Height 計算に effectiveZoom(_mmdZoom) による実ビューポート換算を追加(diagramScrollHeight と同様の zoom 補正パターン)。2. .viewer 基準への変更ではなく wrap.clientWidth/Height * zoom で最小差分にする。3. imageFitSize 自体は変更しない(既存テスト継続で担保)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift build 成功。jest 193件 pass(imageFitSize ロジック自体は無変更)。node script で修正前後の実レンダリング幅を計算し検証: naturalW=4000,naturalH=3000, viewport=1200x800, zoom=2 のケースで、修正前は real width=1066.67(zoom=1のベースラインと同一=ズーム完全キャンセル、バグ再現)、修正後は real width=2133.33(baseline*zoom、正しくズーム反映)。zoom=1 では修正前後で出力が完全一致(TASK-19 のフィット挙動維持)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer.html の _mmdFitImage で、zoom 適用済み #diagram-wrap の clientWidth/clientHeight(ローカル座標系=実ビューポート/zoom)をそのまま imageFitSize に渡していたため、ズーム後にリサイズすると画像がビューポートサイズに再フィットしズームが打ち消される不具合を修正。diagramScrollHeight と同じ手法で、wrap.clientWidth/Height に effectiveZoom(_mmdZoom) を掛けて実ビューポート寸法に換算してから渡すよう変更(viewer.html:313-322)。imageFitSize 自体は無変更。検証: node script で修正前後の実レンダリング幅を計算しズーム打ち消しの再現(修正前1066.67=非ズーム時と同一)と修正(修正後2133.33=baseline×zoom)を確認。zoom=1 では出力が完全一致し TASK-19 の初期フィット挙動を維持。jest 193件 pass、swift build 成功。
<!-- SECTION:FINAL_SUMMARY:END -->
