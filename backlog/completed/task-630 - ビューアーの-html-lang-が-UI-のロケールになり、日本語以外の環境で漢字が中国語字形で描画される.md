---
id: TASK-630
title: ビューアーの html lang が UI のロケールになり、日本語以外の環境で漢字が中国語字形で描画される
status: Done
assignee:
  - '@claude'
created_date: '2026-09-17 04:41'
updated_date: '2026-09-17 04:58'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/pull/678'
modified_files:
  - BefoldApp/viewer-src/bar-mode.ts
  - BefoldApp/BefoldKit/Resources/viewer.html
  - BefoldApp/BefoldKit/ViewerBridge.swift
priority: high
type: bug
ordinal: 827000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #678（ビューアーの操作ラベルのローカライズ）が入れた回帰。viewer.html の `<html lang="ja">` を `lang="en"` に変え、`bar-mode.ts` の `_mmdInitBarModeSwitch()` が `document.documentElement.lang = strings.language || "en"`（`ViewerBridge.uiStringsScript` が渡す `bundle.preferredLocalizations.first`）で上書きするようになった。

実測（オフスクリーン WKWebView + takeSnapshot で `直骨海今前者每步鋼令` を 72px 描画し PNG を SHA-256 比較。システムロケールは -AppleLanguages で切替）:

| ロケール | lang="ja" | lang="en" | 判定 |
|---|---|---|---|
| ja-JP | e76b16ec | e76b16ec | 影響なし |
| en-US | e76b16ec | 101bfd3b | lang="zh-Hans" と完全一致 |
| zh-Hans-CN | e76b16ec | 101bfd3b | 同上 |
| ko-KR | e76b16ec | 720de472 | lang="ko" と一致 |

目視でも 骨・海・者・每・令 の字形が Hiragino Sans → PingFang SC に変わる。原因は `style.css` の body が `-apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif` で CJK を名指ししておらず（`:lang()` / `[lang]` ルールは全 CSS で 0 件）、グリフ選択が WebKit のフォールバック＝lang 依存になっていること。localizations は en / ja の 2 つだけなので、日本語環境以外はすべて en に落ちる。QuickLook プレビューにも同じく及ぶ。

HTML の lang は「そのドキュメント内容の言語」を表す属性で、UI バンドルのロケールではない。befold は表示中ドキュメントの言語を知らないため、ルート要素に UI ロケールを入れる根拠がない。実際 `documentElement.lang` の読み手はコード全体でゼロ（mermaid も locale / fontFamily 未設定）で、ラベルのローカライズは `applyModeLabel()` が textContent / title に直接入れており lang に依存していない。したがってこの 1 行は機能上不要で、削除しても英語 UI のラベルは英語のまま出る。

連鎖して `uiStringsScript` の "language" キーと `ViewerUIStrings.language` も使われなくなる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 英語ロケール（-AppleLanguages "(en-US)"）で日本語文書を描画したときの漢字の字形が、日本語ロケールでの描画と一致する
- [x] #2 documentElement.lang に UI バンドルのロケールを書き込む処理がコード上に存在しない
- [x] #3 uiStringsScript が language キーを注入せず、ViewerBridgeContractTests のキー数の期待値もそれに追随している
- [x] #4 モード名ラベルと Mermaid ズームのツールチップのローカライズは維持されており、既存の viewer テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. bar-mode.ts の documentElement.lang 書き込みを削除
2. uiStringsScript の language キー、ViewerUIStrings.language、関連テストを削除
3. viewer.html の lang は PR 前の ja に戻す（字形を日本語で固定。英語 UI でも従来どおり）
4. en-US ロケールでの字形を実測で確認
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
bar-mode.ts の documentElement.lang 書き込みと、uiStringsScript の language キー / ViewerUIStrings.language を削除し、viewer.html の lang を PR 前の ja に戻した（CJK 字形の固定である旨をコメントで明記）。実測: オフスクリーン WKWebView + takeSnapshot で style.css 適用下の漢字 72px を描画し SHA-256 比較。ja-JP/lang=ja 91147faf、ja-JP/lang=en 91147faf、en-US/lang=ja 91147faf、en-US/lang=en 0ffeccbd。修正後は lang が ja のまま変わらないため英語ロケールでも日本語ロケールと同じ字形になる。JS テストに lang が ja のまま残ることの検査を追加し、lang 書き込みを戻すと落ちることを確認。jest 647 件・swift test 全件合格。
<!-- SECTION:FINAL_SUMMARY:END -->
