---
id: TASK-178
title: charset 未宣言の .htm/.html が文字化けする — 対応要否の検討から行う
status: To Do
assignee: []
created_date: '2026-07-28 01:03'
labels:
  - rendering
  - encoding
  - html
dependencies: []
priority: medium
type: bug
ordinal: 253000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
sample/sample.htm を開くと日本語が文字化けする(添付スクショ)。ファイル自体は妥当な UTF-8 で、<meta charset> が無いだけ。befold は .html/.htm を viewer.html を介さず loadFileURL で WKWebView へ直接ロードする(RendererFeatures.htmlHostFeatures / befold/Viewer/ViewerWebView.swift)。charset 宣言の無い HTML を WebView が既定エンコーディング(日本語環境では Shift_JIS 等)と誤推定し、UTF-8 バイトを二重解釈するため文字化けする。

このタスクは「直すべきか否か」の検討から始める。まず以下を評価し、方針を決めてから(必要なら)実装する。

検討観点:
- そもそも befold として charset 未宣言 HTML の文字化けを直す責務があるか(HTML の仕様上 charset は作者責任、という立場も取りうる)。sample.htm は同梱サンプルなので meta を足すだけで済むが、ユーザーの実ファイルは直らない。
- 直す場合の実現手段と副作用:
  - loadFileURL は charset を指定できない。UTF-8 を仮定して loadHTMLString / loadData(textEncodingName:) へ切り替える案は、相対リソース参照やサンドボックス(allowingReadAccessTo)の扱いに影響する。
  - TextEncoding による自前エンコーディング判定を HTML 直接ロード経路にも通す案。
  - 既定を UTF-8 と仮定して読む案(実運用でどの程度妥当か)。
- 誤検知リスク(本当に Shift_JIS の HTML を UTF-8 と誤って壊さないか)。

成果物として「対応する/しない」の結論と根拠を残す。対応する場合は最小の修正方針まで確定させ、同タスク内で実装・回帰テストまで行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 charset 未宣言 HTML の文字化けに対し befold が対応すべきか否かの結論と根拠が記録される
- [ ] #2 「対応しない」結論の場合: 同梱 sample.htm については文字化けしない状態にする(例: meta charset 追加)か、サンプルとしての意図を明確化する
- [ ] #3 「対応する」結論の場合: 実現手段(loadHTMLString/loadData 切替・自前エンコーディング判定 等)の副作用(相対リソース・サンドボックス・誤検知)を評価した上で最小修正を実装する
- [ ] #4 対応する場合、UTF-8/宣言あり/宣言違いの各 HTML が正しく表示されることを検証する回帰テストを追加する
<!-- AC:END -->
