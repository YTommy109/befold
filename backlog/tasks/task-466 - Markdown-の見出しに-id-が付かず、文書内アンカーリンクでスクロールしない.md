---
id: TASK-466
title: Markdown の見出しに id が付かず、文書内アンカーリンクでスクロールしない
status: To Do
assignee: []
created_date: '2026-08-13 04:29'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 689000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Markdown 表示で `[有効期限の表現](#有効期間の表現)` のような文書内アンカーリンクをクリックしても、該当見出しへスクロールしない。

原因: markdown-it の構成に markdown-it-anchor 相当のプラグインも独自 slug 実装も無く、生成される HTML の見出しに id が一切付与されていない。`BefoldApp/viewer-src/markdown.js:38-75` の `buildMarkdownRenderer()` に `.use(...)` が 1 つも無く、`heading_open` ルールの上書きも無い。`BefoldApp/viewer-src/vendor.js:19-23` の取り込みも highlight.js / markdown-it / dompurify の 3 本のみ。したがって `document.getElementById(id)` は常に null になる。

クリック側 `BefoldApp/viewer-src/reference-clicks.js:44-52` は既に正しい: `#` 始まりの href を preventDefault し、`decodeURIComponent` してから `getElementById` → `[name=]` の順に探し、見つかれば `scrollIntoView({behavior:"smooth"})` する。見つからなければ黙って何もしない（報告の症状と一致）。つまり id さえ振れば日本語見出しでも動く。

注意点: markdown-it は href 側を percent-encode しうるが、クリック側が decode 済みなので **id は decode 済みの生文字列**（GitHub 流 slug: 小文字化・空白→ハイフン・記号除去、非 ASCII はそのまま）で付与すること。id を encode 済みにすると不一致になる。

直接 HTML 表示モードは `BefoldApp/BefoldRenderKit/DirectHTMLLinkPolicy.swift:29-35` が同一文書内フラグメントを allowNativeNavigation にしているため動く。症状は Markdown モード限定のはず。

未確認: 実機 WKWebView での DOM ダンプは未取得（静的解析のみ）。QuickLook 拡張など referenceActivation 無効ホストでの挙動も未検証。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Markdown の h1〜h6 に GitHub 互換 slug の id が付与される
- [ ] #2 日本語見出しへの文書内アンカーリンク（例: `[…](#有効期間の表現)`）のクリックで該当見出しへスクロールする
- [ ] #3 同一 slug が複数ある場合に GitHub と同様の連番サフィックスで一意化される
- [ ] #4 markdown-it が href を percent-encode した場合でも id と一致し、スクロールする回帰テストがある
- [ ] #5 修正を戻すとそのテストが落ちることを確認した
<!-- AC:END -->
