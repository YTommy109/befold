---
id: TASK-19
title: 高解像度JPEGがウィンドウにフィットせず等倍表示されズームしたように見える
status: To Do
assignee: []
created_date: '2026-07-16 07:54'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/223'
type: bug
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
5000x5000px相当の高解像度JPEGを開くと、ラスター画像はウィンドウ幅にフィットせずナチュラルサイズで表示され、ズームしたかのような見た目になる。style.css の #diagram-wrap.image-body が width: max-content; max-width: none で、ウィンドウ幅への追従指定がない設計になっている。一方 SVG は viewer.html の type==='svg' 分岐で max-width: 100% が指定されておりウィンドウ幅にフィットする。ラスター画像とSVGとで挙動が異なっている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ラスター画像(jpeg/png等)も初期表示時はウィンドウサイズにフィットする(横幅だけでなく縦長画像も考慮し高さもフィット対象に含める)
- [ ] #2 既存のズーム機能(⌘+/⌘-/⌘0、Ctrl+ホイール)でフィット状態を基準に拡大縮小できる
<!-- AC:END -->
