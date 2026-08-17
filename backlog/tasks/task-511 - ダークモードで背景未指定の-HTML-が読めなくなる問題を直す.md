---
id: TASK-511
title: ダークモードで背景未指定の HTML が読めなくなる問題を直す
status: To Do
assignee: []
created_date: '2026-08-17 10:35'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 740000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状

ダークモードで `.html` / `.htm` を開くと、文字がほぼ読めない。実例: `sample/sample.html` は `body { color: #24292f }` を指定するが `background` を指定していないため、`#24292f` の文字が befold のダークキャンバス `#1E1E1E` の上に載る。

## 原因

befold は HTML 描画で前景色（文字色）を文書に委ね、背景色（キャンバス）は befold 側が保持している。所有権が割れているのが原因。

- `BefoldApp/BefoldRenderKit/ViewerWebViewFactory.swift:87` が `drawsBackground = false` を強制し、WebKit の既定のキャンバス描画を殺している
- キャンバス色は `BefoldApp/befold/Viewer/ViewerTheme.swift:11-16`（dark = `#1E1E1E`）
- iframe/srcdoc 経路（`BefoldApp/viewer-src/renderers.ts:111-135`、QuickLook 等）にも背景指定がない

Markdown / コード / CSV / Mermaid は befold が前景色も背景色も持つため問題にならない。HTML だけが例外。

## ブラウザの挙動（あるべき姿）

キャンバス色は UA スタイルシートではなく `color-scheme` が決める。

| ページの宣言 | OS ダーク時にブラウザが塗る背景 |
| --- | --- |
| `color-scheme` 宣言なし（light-only 扱い） | 白 |
| `color-scheme: light dark` / `dark` を宣言 | ダーク（WebKit は概ね `#1E1E1E`） |

ブラウザはダーク対応を名乗っていないページを勝手にダーク背景へ置かない。befold はそれを無視して全ページへダークキャンバスを適用している。なお `ViewerTheme.swift:12` のコメントにあるとおり `#1E1E1E` はもともと WebKit の Canvas 相当値。

## 方針

独自のデフォルト CSS を注入するのではなく、**HTML 文書にはキャンバスごと明け渡す**（＝ WebKit の既定動作の上書きをやめる）。これなら分岐ロジックを持たずに両ケースが成立する。

## 検討すべき点

1. ダークウィンドウの中に白い矩形が出る見え方になる（ブラウザ相当だが他形式と見た目が揃わない）
2. `drawsBackground` は Markdown 等と同一 WebView で共有する設定のため、直接 HTML モードの出入りに合わせた切り替えが要る（共通経路の不変条件に触る）
3. iframe/srcdoc 経路にも同じ手当てが要る
4. `BefoldApp/BefoldKit/Resources/style.css:1-8` と `ViewerTheme.swift` の「キャンバス色はネイティブが唯一の定義」というルールに、HTML だけは文書が所有するという例外の明記が要る

## 未実測の前提

「WKWebView で `drawsBackground` を戻せば `color-scheme` に応じて白／ダークを塗り分ける」は未検証。`color-scheme` 宣言あり／なしのサンプル 2 本を用意して実機で確認すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `color-scheme` を宣言していない HTML（背景未指定・暗い文字色）が、OS ダークモードで白背景に描画され読める
- [ ] #2 `color-scheme: light dark` を宣言した HTML が、OS ダークモードでダーク背景に描画される
- [ ] #3 直接ロード経路（本体アプリ）と iframe/srcdoc 経路（QuickLook 等）の両方で上記が成立する
- [ ] #4 HTML から他形式（Markdown 等）へ切り替えた後、キャンバスが従来どおり `ViewerTheme.canvas` に戻る
- [ ] #5 `style.css` 冒頭と `ViewerTheme.swift` の設計コメントに HTML の例外が明記されている
- [ ] #6 実装着手前に `/review-design` を回し、結果を Implementation Plan に反映している
<!-- AC:END -->
