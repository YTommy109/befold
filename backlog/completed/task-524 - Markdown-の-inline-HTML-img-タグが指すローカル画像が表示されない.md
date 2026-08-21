---
id: TASK-524
title: Markdown の inline HTML img タグが指すローカル画像が表示されない
status: Done
assignee:
  - '@claude'
created_date: '2026-08-18 16:15'
updated_date: '2026-08-19 03:31'
labels: []
dependencies: []
references:
  - BefoldApp/BefoldKit/MarkdownImageEmbedder.swift
  - BefoldApp/BefoldKit/Resources/viewer.html
  - BefoldApp/BefoldRenderKit/ViewerWebViewFactory.swift
  - BefoldApp/viewer-src/markdown.ts
  - BefoldApp/BefoldRenderKit/DirectHTMLModeController.swift
priority: medium
type: bug
ordinal: 764000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 事象

Markdown 文書に inline HTML の `<img src="relative/path.png">` を書くと、befold のプレビューで画像が表示されない。同じ画像を Markdown 記法 `![alt](relative/path.png)` で書けば表示される。実例として、リポジトリの README.md はヒーロー画像と機能ギャラリーに `<img>` を 5 行使っており、befold で開くと画像が 1 枚も出ない。

GitHub の README は中央寄せ・幅指定・表内配置のために inline HTML の `<img>` を使わざるを得ない（Markdown 記法では表現できない）。つまり「GitHub 向けに書いた Markdown を befold で確認する」という、このアプリの中心的な用途で画像が欠ける。

## 確認済みの原因（実測・コード参照）

ローカル画像の表示は「Swift 側のプリプロセスで画像参照を base64 data URI へ置換する」方式でのみ実現されており、inline HTML の `<img>` がその置換対象になっていない。

1. **置換の正規表現が Markdown 記法限定**: `BefoldApp/BefoldKit/MarkdownImageEmbedder.swift:73` の `imagePattern` は `![...](...)` のみに一致する。さらに `MarkdownImageEmbedder.swift:47` の `guard markdown.contains("![")` で早期リターンするため、`<img` を含むだけの文書は走査すらされない
2. **CSP が data URI 以外のローカル画像を禁止**: `BefoldApp/BefoldKit/Resources/viewer.html:17` が `img-src 'self' data:`。これは意図的な設計で、`MarkdownImageEmbedder.swift:3-6` のコメントに「data URI にすることで CSP 変更を不要にする」と明記されている
3. **読み取り許可がドキュメント側を含まない**: `BefoldApp/BefoldRenderKit/ViewerWebViewFactory.swift:61-63` の `loadFileURL(_:allowingReadAccessTo:)` は BefoldKit の Resources ディレクトリのみを許可する。よって `<img>` の相対 src はアプリバンドル内を基準に解決され、存在しない file URL になる
4. **サニタイズは無関係**: `BefoldApp/viewer-src/markdown.ts:36-41` の DOMPurify は設定なしで呼ばれ、`<img>` / `src` / `width` / `alt` はデフォルトで許可される。markdown-it も `html: true`（`BefoldApp/viewer-src/markdown.ts:127`）なのでタグ自体は DOM に残る

未検証: 実機での失敗が「file URL の 404」と「CSP 違反」のどちらで先に落ちるかは Web インスペクタで確認していない（表示されない結論は変わらない）。

## 実装方針の候補（調査時点の見立て。着手時に判断すること）

- **案 A: Swift の置換に `<img>` パターンを足す**（侵襲小）。既存の `dataURI(forPath:baseURL:)` と `ReferenceResolver` を再利用でき、CSP も `allowingReadAccessTo` も触らない。代償は正規表現が 2 本になること、コードフェンス除外ロジックを共用させる必要があること、属性の書き方の網羅が要ること
- **案 B: 置換をレンダリング後の DOM 側へ移す**（構造的な単純化）。markdown-it は `![]()` も結局 `<img src>` に変換するため、レンダリング後に `img[src]` を走査して data URI を入れれば記法 2 種を 1 つの機構で扱える。コードフェンス／インラインコード除外ロジックが丸ごと不要になり、正規表現の網羅漏れという事故の型が消える。代償は Swift↔JS の非同期ブリッジが 1 本増えることと、段階描画（チャンク追記）との噛み合わせの再設計
- **案 C: CSP に `file:` を足し、読み取り許可をドキュメント隣接ディレクトリへ広げる** — サンドボックス設計（task-1.9 / task-1.12）に逆行するため推奨しない。なお直接 HTML モードは `BefoldApp/BefoldRenderKit/DirectHTMLModeController.swift:98-101` で隣接ディレクトリを許可しており、viewer.html モードとは方針が分かれている

## スコープ外

リモート URL の画像（`https://` の shields.io バッジ等）は CSP と「ネットワークへ出ない」設計により表示しない。これは意図した挙動であり、本タスクでは変更しない。対象はあくまでローカルファイルを指す `<img>` に限る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 inline HTML の img タグの src が相対パスで指すローカル画像がプレビューに表示される
- [x] #2 src が絶対パス・file URL・上位相対パス（../）の場合も同様に表示される
- [x] #3 src をシングルクォートで囲んだ場合や、属性順序が異なる場合（width が src より前など）でも表示される
- [x] #4 コードフェンス内・インラインコードスパン内に書かれた img タグは置換されず、原文のまま表示される
- [x] #5 リモート URL を指す img タグは従来どおり原文のまま残り、挙動が変わらない
- [x] #6 読み込み失敗・非対応拡張子・サイズ上限超過の img タグは原文のまま残り、既存の Markdown 記法と同じ縮退をする
- [x] #7 上記を検証するユニットテストがあり、修正を戻すと落ちることを確認している
- [x] #8 リポジトリの README.md を befold で開き、ヒーロー画像と機能ギャラリーの画像が表示されることを実機で確認している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 方針は案 A（Swift のプリプロセスで <img src> も data URI へ置換）を採る。案 B（DOM 側へ移す）は、チャンク追記が「そのチャンク単体を markdown レンダーして insertAdjacentHTML」する構造（viewer-src/render.ts:203-213）のため、非同期ブリッジ 1 本の追加では済まず段階描画の再設計になる。CSP は data: を既に許可しており、案 A は CSP も allowingReadAccessTo も触らない。
2. 単純化: 正規表現を 2 本に増やすが、置換ループは 1 本に畳む。embedImages(inLine:) を「(range, 置換文字列) の列を作って 1 回で組み立てる」形へ一般化し、コードスパン除外・カーソル再構築を両記法で共有する（現状の Markdown 記法専用ループを拡張しない）。
3. <img> の解析は 2 段階にする。タグ本体 <img ...> を取り、その中で src 属性値（ダブル/シングル/裸）を別途取る。属性順序（AC#3）とクォート種別を 1 本の巨大な正規表現に押し込まない。
4. 早期リターンの guard を markdown.contains("![") から「![ または <img（大文字小文字無視）を含む」へ広げる。
5. AC#2 の file URL は ReferenceResolver.classify が scheme=file を .unsupported にしているため現状は Markdown 記法でも通らない。絞り込み点である ReferenceResolver 側で file: を .local へ回す（画像だけの特別扱いにしない）。ReferenceResolverTests にケースを足す。
6. テストは MarkdownImageEmbedderTests に <img> 系を追加（相対・絶対・file URL・../・シングルクォート・属性順序・フェンス内・インラインコード内・リモート・非対応拡張子・サイズ上限）。修正を戻すと落ちることを確認する。
7. 実機で README.md を befold で開き、ヒーロー画像と機能ギャラリーが出ることを確認する。
8. 既知の限界（<img> が複数行にまたがる場合は行単位処理のため対象外）を Notes に残す。

9. [設計レビュー反映] <img> のタグ本体はクォート認識のパターンで取る（<img\b((?:[^>"']|"[^"]*"|'[^']*')*)>）。alt="a > b" のような属性値の中の > でタグ末尾を誤認しないため。
10. [設計レビュー反映] 表示可否は Swift だけでは決まらない。![]() は markdown-it の validateLink（viewer-src/markdown.ts:29-32、data:image/ を明示許可）、生 HTML は DOMPurify という別の関門を通る。DOMPurify が data URI の <img> を保持することを BefoldKit/Resources/__tests__ 側のテストでピン留めする（実測では保持することを確認済み）。
11. [設計レビュー反映] 高頻度経路（チャンク追記ごとの全行走査）のコストを増やさない。文書全体の早期リターンを「![ または <img を含む」に広げ、行単位でも <img を含む行だけ <img> パターンを走らせる。
12. [設計レビュー反映] MarkdownImageEmbedderTests は実測 247 行で追加分を足すと閾値 400 に近づくため、<img> 系のテストは別の型（別ファイル）に分ける。MarkdownImageEmbedder 本体は実測 156 行 → 見積 215 行で閾値内。
13. [設計レビュー反映] file: を ReferenceResolver で扱う変更は、画像だけでなくリンクのリンク化・クリック時オープンにも及ぶ挙動変更である。意図した拡張として Notes に明記し、ReferenceResolverTests にケースを足す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

案 A（Swift のプリプロセスで <img src> も data URI へ置換）を採用した。案 B（DOM 側へ移す）は、チャンク追記が「そのチャンク単体を markdown レンダーして insertAdjacentHTML」する構造（viewer-src/render.ts:203-213）のため、非同期ブリッジ 1 本の追加では済まず段階描画の再設計になる。

単純化: 記法ごとに文字列を組み立て直す形をやめ、両記法とも「パス部分の範囲 → data URI」の置換列に落として 1 度で組み立てる形にした。結果として alt・title・その他の属性は原文のまま残り、コードスパン除外と再構築のロジックが記法間で共有される。markdown 記法側の置換も alt/title を再構築しなくなった。

<img> の解析は 2 段階（タグ本体 → src 属性）。タグ本体のパターンはクォート内を読み飛ばすため、alt="a > b" のように属性値へ > が現れてもタグ末尾を誤認しない。

## file: スキームの扱い（意図した挙動変更）

AC#2 の file URL は ReferenceResolver.classify が scheme=file を .unsupported にしていたため、Markdown 記法でも通っていなかった。画像だけの特別扱いにせず絞り込み点である ReferenceResolver で直したので、**リンクのリンク化・クリック時オープンにも及ぶ**。file:///path は絶対パス /path と同じものの別表記であり、絶対パスは既に扱えていたため新しい能力は増えない。ReferenceResolverTests に 3 ケース（通常・パーセントエンコード・大文字スキーム）を追加。

## 検証（実測）

- swift test 全件 pass（1659 tests / 266 suites）。JS は jest 539 tests pass、oxlint / oxfmt もクリーン
- 修正を戻すと新テストが落ちることを確認（MarkdownImageEmbedderInlineHTMLTests + ReferenceResolverTests で 11 tests / 17 issues 失敗）
- 実 README.md を実 embedder に通した結果: <img src= 9 箇所すべてが data URI になり、site/ 相対の残りは 0（出力 2.1MB）
- その出力を実アプリと同じ viewer.html + CSP 下の WKWebView へ render した結果、9 枚すべて naturalWidth 1280 でデコード成功（AC#8 はこの経路で確認。GUI の目視は未実施）
- scripts/webview-smoke.swift に inline HTML の data URI 画像が描画されることの検証を追加（幅指定 + 中央寄せ付き）。スモーク全体 PASS
- viewer.test.js に DOMPurify が data: URI の <img> を保持することの検証を追加。![]() 側は markdown-it の validateLink が通すが生 HTML はそこを通らないため、両方の関門を別々にピン留めした

## 既知の限界

- <img> が複数行にまたがる場合は対象外（フェンス判定が行単位のため、処理も行単位）。README の書き方（1 行 1 タグ、表の 1 行に複数タグ）は対象内
- 画像 9 枚で 2.1MB の文字列を evaluateJavaScript へ渡すことになる。既存の ![]() 記法と同じ性質で、本タスクでは変えていない

## 派生（スコープ外）

Description の「リモート URL の画像は CSP により表示しない。これは意図した挙動」という前提は**誤りだった**。実測でリモート画像は読み込まれ、securitypolicyviolation も発火しない。TASK-526 として起票した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MarkdownImageEmbedder が inline HTML の <img src> も data URI へ差し替えるようにした。両記法を「パス範囲 → data URI」の置換列へ畳んで 1 経路にし、file: スキームは絞り込み点の ReferenceResolver で扱う。実 README.md の <img> 9 箇所が data URI になり、実 CSP 下の WKWebView で 9 枚とも naturalWidth 1280 でデコードできることを実測。swift test 1659 / jest 539 pass、修正を戻すと新テスト 11 件が落ちることも確認。
<!-- SECTION:FINAL_SUMMARY:END -->
