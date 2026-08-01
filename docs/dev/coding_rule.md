# befold コーディング規約

このドキュメントは befold プロジェクトのコーディング規約群への**インデックス**である。
規約の実体はレビュー対象（消費者）別に分割済み。CLAUDE.md・スキル・コマンドは
このファイル、または下記の分割後ファイルを直接参照する。

**CLAUDE.md との関係**: アーキテクチャ図・プロジェクト構成・技術スタックの単一情報源は
[`./native-app-design.md`](./native-app-design.md) であり、`.claude/CLAUDE.md` は
その要約版を持つ。coding_rule.md およびこの下の各ファイルはコーディング規約
（型設計・命名・テスト・コミット等の「書き方」のルール）のみを扱い、
アーキテクチャ・構成の記述はここでは重複させない。native-app-design.md を更新したら
`.claude/CLAUDE.md` の対応セクションも同じ diff 内で同期する（権威元は native-app-design.md）。

## 分割構成

| ファイル | 内容 | 主な読者 |
|---|---|---|
| [`./rules/product-code.md`](./rules/product-code.md) | Swift コーディング規約（Concurrency・型設計・命名・パターン・責務分離・共通化/単一情報源/DI・AppKit/SwiftUI 混在・WKWebView/JS ブリッジ）+ JavaScript コーディング規約 + エラーハンドリング規約 + コード品質ツール（SwiftLint/SwiftFormat） | `review-swift-code` スキル |
| [`./rules/testing.md`](./rules/testing.md) | テスト規約全体（Swift Testing・Jest・共有ヘルパー・Unit/Integration 分離・テストパターン・パラメタライズ・テスト対象外・CI 時間/並列性ルール） | `review-swift-tests` スキル |
| [`./rules/comments.md`](./rules/comments.md) | コメント・ドキュメンテーション規約（プロダクトコード / テストコード共通） | `review-swift-code` / `review-swift-tests` 両スキル |
| [`./rules/workflow.md`](./rules/workflow.md) | コマンド + コミット規約 + 品質チェック手順 + レビュー対応方針 + 応答言語 | メインエージェント |

規約を更新するときは、対象の分割後ファイルを直接編集する。このインデックスファイル
自体には規約本文を置かない。

## 参照元

- `.claude/skills/review-swift-code.md`: `product-code.md` + `comments.md` を読む
- `.claude/skills/review-swift-tests.md`: `testing.md` + `comments.md` を読む
- `.claude/commands/quality-loop.md`: 全ラウンドで `product-code.md` + `testing.md` +
  `comments.md` + `workflow.md`（4 ファイル）を読む

## 歴史的参照について

`docs/superpowers/` 配下の過去の plan / spec ドキュメントは、分割前の
`docs/dev/coding_rule.md` を参照している箇所がある。これらは当時の設計判断の記録
（履歴）であり書き換えない。このインデックスファイルが存置されることで、
リンク先としての到達性は保たれる。
