---
id: TASK-19
title: 高解像度JPEGがウィンドウにフィットせず等倍表示されズームしたように見える
status: Done
assignee: []
created_date: '2026-07-16 07:54'
updated_date: '2026-07-16 16:55'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/223'
priority: medium
type: bug
ordinal: 90
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
5000x5000px相当の高解像度JPEGを開くと、ラスター画像はウィンドウ幅にフィットせずナチュラルサイズで表示され、ズームしたかのような見た目になる。style.css の #diagram-wrap.image-body が width: max-content; max-width: none で、ウィンドウ幅への追従指定がない設計になっている。一方 SVG は viewer.html の type==='svg' 分岐で max-width: 100% が指定されておりウィンドウ幅にフィットする。ラスター画像とSVGとで挙動が異なっている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ラスター画像(jpeg/png等)も初期表示時はウィンドウサイズにフィットする(横幅だけでなく縦長画像も考慮し高さもフィット対象に含める)
- [x] #2 既存のズーム機能(⌘+/⌘-/⌘0、Ctrl+ホイール)でフィット状態を基準に拡大縮小できる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
調査結果: #diagram-wrap.image-body が width:max-content; max-width:none で常にナチュラルサイズ描画。既存のグローバルズーム(_mmdZoom, wrap.style.zoom)は他の表示種別(code-body/markdown-body等)と同様、wrap自体の実寸を基準に乗算するだけで、fit用の新しい状態は不要。

単純化の検討: SVG分岐のような .diagram-zoom-wrap 経路(per-diagram zoom, onload計測)を新設せず、既存の「wrap を100%サイズにしてzoomがそれを乗算する」パターン(code-body/markdown-body と同型)を画像にも適用するだけで両ACを満たせる。新しいJS状態・onloadハンドラは不要。

実装方針(CSS のみ):
1. style.css #diagram-wrap.image-body: width:max-content/max-width:none/margin:auto を撤廃し、width:100%; height:100%; display:flex; align-items:center; justify-content:center; に変更(wrapを常にビューポート枠いっぱいにし、中で画像を中央寄せ)
2. #diagram-wrap.image-body img: max-width:100%; max-height:100%; width:auto; height:auto; を追加(縦横ともに枠に収まるよう縮小、小さい画像は拡大しない)
3. コメントを新しい設計に合わせて更新
4. 既存の .viewer:has(> #diagram-wrap.image-body) の padding:16px/justify-content:flex-start はそのまま維持(zoom>1で拡大した際のオーバーフロー方向は他の表示種別と同じ挙動になるため変更不要)
5. JS/zoom定数(ZOOM_MIN/MAX/STEP/DEFAULT, effectiveZoom)は変更なし。既存のCmd+/Cmd-/Cmd0/Ctrl+wheelがそのままfit状態を基準に流用される
6. 目視確認: befold アプリをビルドして高解像度JPEG/PNG(横長・縦長)を開き、初期表示でウィンドウに収まること、既存ズーム操作で拡大縮小できることを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了: style.css の #diagram-wrap.image-body を width:100%/height:100%/flex中央寄せに変更し、img は viewer.html の _mmdFitImage() が naturalWidth/naturalHeight と wrap.clientWidth/clientHeight から算出したフィットサイズを px 実数値で style.width/height に設定する(viewer.js の新規 imageFitSize、単体テスト4件追加)。px 実数値にしたのは % のままだと祖先 #diagram-wrap の CSS zoom と相殺され既存のグローバルズームが効かなくなるため(検証で実測: %のみだと .viewer.scrollWidth がズームしても変化せず、px化後は zoom 1→1.5 で 800→1168 に増加し正しく拡大されることを確認)。ウィンドウリサイズ時も再フィットするよう resize リスナーを拡張。手動検証: swift スクリプトで WKWebView に viewer.html を読み込み、横長(4000x1000)/縦長(800x3000)/小さい(200x100)画像それぞれで初期フィット・Cmd+相当のズーム・リサイズ後再フィットを確認済み。npm test 189件・swift build・webview-smoke.swift いずれもパス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
#diagram-wrap.image-body を wrap全面フィット(width/height:100%,flex中央寄せ)に変更し、img は viewer.js の imageFitSize()(naturalWidth/Height と利用可能領域からアスペクト比維持でフィットサイズを算出、単体テスト4件)を viewer.html の onload/resize で呼び出し px 実数値の style.width/height として適用。px化により既存のグローバルズーム(#diagram-wrap の CSS zoom, Cmd+/Cmd-/Cmd0/Ctrl+ホイール)がフィット状態を基準にそのまま乗算で効く(% のままだと相殺されて効かなくなることを実測で確認し設計変更)。検証: npm test 189件パス、swift build 成功、webview-smoke.swift パス、加えて WKWebView を直接駆動するアドホック検証スクリプトで横長/縦長/小さい画像の初期フィット、ズーム操作後の.viewer.scrollWidth変化(800→1168、zoom1→1.5相当)、ウィンドウリサイズ後の再フィット(768px→368px)を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
