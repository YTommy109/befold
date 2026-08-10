---
id: TASK-422
title: viewer の重複ヘルパーを統合する
status: To Do
assignee: []
created_date: '2026-08-10 07:29'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 509200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
レビューで確認した重複・無意味な間接参照をまとめて解消する。個別には小さいが、いずれも「片方だけ直すと 2 つの表示が食い違う」形になっている。

1. _sourceLanguage の複製（viewer-main.js:1762-1764 と :1772-1776）: _renderSource が `(type === "svg" || type === "html") ? "xml" : (type === "md") ? "markdown" : lang || "plaintext"` をインラインで持ち、10 行下の _sourceLanguage(type, lang) と同一内容。ヘルパー側のコメントは「差分表示と通常表示で同じ規則を使う」と書いているが、呼んでいるのは差分経路だけ。型を 1 つ足すと通常表示と差分表示でハイライト言語がずれる。

2. _escapeHtml の重複（viewer-main.js:1103 vs viewer.js:180）: viewer.js の escapeHtml は純粋関数で Node テスト済み。viewer-main.js 側は DOM を使う複製で、呼び出しは _renderMmd（:1535）の 1 箇所のみ。呼び出しごとに捨てる <div> を作り、`"` をエスケープしない。viewer.js は同一スコープで先に読み込まれるため置き換えられる。

3. 差分マーカーの三項演算の複製（viewer.js:467 と :552）: `line.type === "add" ? "+" : (line.type === "del" ? "-" : " ")` がインライン表示と左右分割表示に逐語で 2 回。:464 のコメントは色に依らず add/delete を区別するためのグリフだと説明しており、片方を直し忘れると 2 つのレイアウトが同じハンクで食い違う。

4. effectiveZoom の恒等関数（viewer.js:78）: `function effectiveZoom(zoom) { return zoom; }` が export され viewer.js:87,88 と viewer-main.js:118,119,123,469 から呼ばれている。読み手に変換があるかのように見せて定義を開かせるだけの間接参照で、将来 1 箇所だけに変換を足す事故を誘う。

5. writeToPasteboard の重複（ViewerWindowController.swift:655）: doc コメント自体が「FileListView の copyPath と同じ処理」と書いており、FileListView.swift:253-257 に同じ clearContents / setString(forType:.string) がある（copyFileReference :247 が 3 つ目の変種）。相対パスの算出も referenceBaseURL と model.baseDirectory?.url ?? rootDirectory で基準が異なるため、「相対パスをコピー」の挙動変更を 2 回行う必要があり、2 つのメニューが黙ってずれる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 _renderSource が _sourceLanguage を呼ぶ（言語判定の実装が 1 箇所になる）
- [ ] #2 viewer-main.js の _escapeHtml が撤去され viewer.js の escapeHtml に一本化される
- [ ] #3 差分マーカーのグリフ決定が 1 箇所になる
- [ ] #4 effectiveZoom が撤去され呼び出し側が値を直接使う（または実体のある変換になる）
- [ ] #5 ペーストボード書き込みと相対パス算出が共通化され、サイドバーとウィンドウのメニューで同じ結果になる
- [ ] #6 既存の Node テストと swift test が通る
<!-- AC:END -->
