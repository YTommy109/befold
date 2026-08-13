---
id: TASK-466
title: Markdown の見出しに id が付かず、文書内アンカーリンクでスクロールしない
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-13 04:29'
updated_date: '2026-08-13 05:37'
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
- [x] #1 Markdown の h1〜h6 に GitHub 互換 slug の id が付与される
- [x] #2 日本語見出しへの文書内アンカーリンク（例: `[…](#有効期間の表現)`）のクリックで該当見出しへスクロールする
- [x] #3 同一 slug が複数ある場合に GitHub と同様の連番サフィックスで一意化される
- [x] #4 markdown-it が href を percent-encode した場合でも id と一致し、スクロールする回帰テストがある
- [x] #5 修正を戻すとそのテストが落ちることを確認した
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 前提を実測で確認する（DOMPurify が id を落とさないか、markdown-it-anchor 追加が必要か）
2. 依存を増やさず、markdown.js 内に GitHub 互換 slug（slugifyHeading / uniqueHeadingSlug）と core ルール befold_heading_ids を足す
3. 実インスタンス（markdownRenderer()）を使った jest テストを書く。日本語・percent-encode・重複・描画をまたぐ状態漏れを固定する
4. core ルールの配線を外して 7 件が落ちることを確認する
5. viewer-bundle.js を再ビルドしてコミットする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 前提の検証（実装前）

- DOMPurify は id を落とさない: markdown.js:23-25 の sanitizeRenderedHtml は purify.sanitize(html) を設定なしで呼ぶだけで、DOMPurify 3.4.12 の既定は id を許可する。非 ASCII の id も round-trip する（dompurify 3.4.12 + jsdom 25 で実測）。よって slug を振るだけで足りる。
- 起票時の記載どおり buildMarkdownRenderer() に .use() も heading_open 上書きも無し（markdown.js:41-73）、vendor.js:19-22 は highlight.js / markdown-it / dompurify のみ。クリック側 reference-clicks.js:46-52 は decodeURIComponent → getElementById で既に正しい。

## 設計判断: markdown-it-anchor を足さず自前 slug にした

新しい npm 依存を足すと scripts/check-third-party-licenses.mjs のパッケージ表と THIRD_PARTY_LICENSES.md、および vendored-deps のバージョン表の 3 箇所を同期する義務が発生する。slug 生成は 20 行程度で、GitHub 流の規則もこちらで固定したいため（percent-encode しないことがクリック側との契約）、viewer-src 内の純粋関数にした。

## 実装

- markdown.js に headingTextOf / slugifyHeading / uniqueHeadingSlug / assignHeadingIds を追加し、instance.core.ruler.push('befold_heading_ids', assignHeadingIds) で配線した。
- slug は inline トークンの children から text / code_inline だけを連結して作る（inline.content だと `**` が残り GitHub とずれる）。
- 一意化の Map は assignHeadingIds の中で描画ごとに作るため、連番が前の描画へ漏れない（テストで固定）。
- 連番候補が別見出しの素の slug と衝突する場合は空き番号まで送る。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
markdown-it の core ルール befold_heading_ids を追加し、h1〜h6 に GitHub 互換 slug の id を振るようにした。依存は増やさず viewer-src/markdown.js 内の純粋関数（slugifyHeading / uniqueHeadingSlug）で実装している。id は decode 済みの生文字列で振るため、markdown-it が href を percent-encode しても、クリック側（reference-clicks.js）の decodeURIComponent 後のキーと一致する。検証: 新規テスト viewer-markdown-heading-ids.test.js 14 件が通り、core ルールの配線を外すと 7 件が落ちることを確認した。npm test 全体 431 件、eslint / tsc --noEmit / check:viewer-cycles も通過。
<!-- SECTION:FINAL_SUMMARY:END -->
