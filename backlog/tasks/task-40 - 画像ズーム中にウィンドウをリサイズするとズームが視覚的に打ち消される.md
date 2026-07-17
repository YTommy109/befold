---
id: TASK-40
title: 画像ズーム中にウィンドウをリサイズするとズームが視覚的に打ち消される
status: To Do
assignee: []
created_date: '2026-07-17 02:07'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
viewer.html の _mmdFitImage(:315) は wrap.clientWidth/clientHeight を #diagram-wrap から取得するが、この要素自体に CSS zoom が適用されている(viewer.html:93 `wrap.style.zoom = effectiveZoom(_mmdZoom)`)。zoom=z のとき clientWidth はローカル座標系で viewport/z を返すため、リサイズハンドラ(:322-329)経由の再フィットで画像が viewport/z ローカルpx にフィットされ、レンダリング結果はちょうどビューポートサイズ = ズームが視覚的に打ち消される(_mmdZoom は z のまま)。永続化されたズームが img.onload 前に適用される初回表示でも同様。

修正方向: フィット計算の基準を zoom 非適用の親要素(.viewer)の寸法にする、または diagramScrollHeight(viewer.js:79)と同様に globalZoom で補正する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ラスター画像をズーム(≠1)した状態でウィンドウをリサイズしてもズーム倍率が維持される
- [ ] #2 永続化ズームがある状態での初回表示がフィット×ズームの設計(viewer.html の記述どおり)で描画される
- [ ] #3 ズーム=1 でのウィンドウフィット挙動(TASK-19 の修正)は維持される
<!-- AC:END -->
