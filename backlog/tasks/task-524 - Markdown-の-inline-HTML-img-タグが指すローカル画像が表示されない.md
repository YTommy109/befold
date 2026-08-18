---
id: TASK-524
title: Markdown の inline HTML img タグが指すローカル画像が表示されない
status: To Do
assignee: []
created_date: '2026-08-18 16:15'
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
- [ ] #1 inline HTML の img タグの src が相対パスで指すローカル画像がプレビューに表示される
- [ ] #2 src が絶対パス・file URL・上位相対パス（../）の場合も同様に表示される
- [ ] #3 src をシングルクォートで囲んだ場合や、属性順序が異なる場合（width が src より前など）でも表示される
- [ ] #4 コードフェンス内・インラインコードスパン内に書かれた img タグは置換されず、原文のまま表示される
- [ ] #5 リモート URL を指す img タグは従来どおり原文のまま残り、挙動が変わらない
- [ ] #6 読み込み失敗・非対応拡張子・サイズ上限超過の img タグは原文のまま残り、既存の Markdown 記法と同じ縮退をする
- [ ] #7 上記を検証するユニットテストがあり、修正を戻すと落ちることを確認している
- [ ] #8 リポジトリの README.md を befold で開き、ヒーロー画像と機能ギャラリーの画像が表示されることを実機で確認している
<!-- AC:END -->
