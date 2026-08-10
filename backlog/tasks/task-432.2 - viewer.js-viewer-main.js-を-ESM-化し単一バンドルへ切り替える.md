---
id: TASK-432.2
title: viewer.js / viewer-main.js を ESM 化し単一バンドルへ切り替える
status: To Do
assignee: []
created_date: '2026-08-10 12:56'
updated_date: '2026-08-10 12:57'
labels: []
dependencies:
  - TASK-432.1
parent_task_id: TASK-432
priority: medium
type: chore
ordinal: 674000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現行 2 ファイルを ES モジュールへ変換し、esbuild で単一の IIFE 成果物へまとめて `viewer.html` の読み込みを差し替える。**責務の分割はこのサブタスクでは行わない**（振る舞いとファイル構成を保ったまま、依存の表現方法だけを変える）。分割は次のサブタスクで行う。

このサブタスクは分割できない。ESM 化するとテスト側のハーネスが同時に成立しなくなるため、テスト移行まで含めて 1 単位になる。

## 現状（実測）

- `viewer-main.js` は `viewer.js` の識別子を裸の名前で参照する（`:27` ZOOM_DEFAULT、`:47` parseStoredZoom、`:577` mermaidTheme、`:653` highlightCode、`:661` sanitizeRenderedHtml、`:1694` renderShape ほか）。これを import へ置き換える。
- ベンダーライブラリも防御的なグローバル参照になっている（`:645` `typeof markdownit === undefined` のチェック、`:653` の `typeof hljs`）。扱いを決めること。
- 両ファイル末尾に jest 用の CommonJS エクスポート境界がある（`viewer.js:874` / `viewer-main.js:1823`）。ESM 化で不要になる。
- テストは 6 ファイル 3,716 行・370 ケース、すべて `require()`。`__tests__/support/viewerMainHarness.js`（144 行）が jsdom へ `viewer.html` を読み込み、`window.eval` で viewer.js → viewer-main.js の順に評価してグローバル共有を再現している（`:61-64`, `:83-89`）。ESM 化でこの方式は成立しない。
- `befoldTests/ViewerBridgeContractTests.swift` は JS を文字列として読んで契約を検証しており、`viewer.html` / `viewer.js` / `viewer-main.js` へのリテラル参照が 11 箇所ある。

## 最大のリスクと対策

裸のグローバル参照を import へ置き換える際、**付け忘れた識別子はバンドル時にエラーにならず実行時に初めて落ちる**。型検査または同等の未定義参照検出（`no-undef` 相当）をこの作業の前に有効化し、機械的に検出できる状態で変換すること。ADR 0005 の Decision に明記した要件。

## 注意

- mermaid はバンドルに含めない。`viewer-main.js:605-608` に「3.2MB は mermaid 不使用プレビューでは無駄なパースコストになるため描画の瞬間まで遅延する」と設計意図が記録されており、`:614` の `script.src = mermaid.min.js` による DOM 挿入ロードを維持する。
- CSP を変更しないこと。`viewer.html:17` は `script-src self` で、`ViewerBridgeContractTests.swift:179-191` が `unsafe-inline` の不在とインライン script の不在を検証している。esbuild の `format: iife` はこの制約に適合する。
- `viewerMainHarness.js` は `viewer.html` の実体を読み込んでいるため、HTML の構造変更がテストに直結する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer.js / viewer-main.js が import / export で依存を表現している
- [ ] #2 viewer.html が単一のバンドル成果物を読み込む形になっている
- [ ] #3 ESM 化の前に未定義参照を機械検出する仕組みが有効になっており、変換後の検出結果がゼロである
- [ ] #4 既存の 370 ケースが通る（ケース数が減っていない）
- [ ] #5 ViewerBridgeContractTests が成果物を見る形に向け直され、通る
- [ ] #6 mermaid.min.js がバンドルへ取り込まれておらず、遅延ロードのまま動作する
- [ ] #7 CSP が変更されていない
- [ ] #8 本体アプリと QuickLook 拡張の双方で表示が変わらないことを確認する
<!-- AC:END -->
