---
id: TASK-422
title: viewer の重複ヘルパーを統合する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 07:29'
updated_date: '2026-08-11 23:58'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 116000
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
- [x] #1 _renderSource が _sourceLanguage を呼ぶ（言語判定の実装が 1 箇所になる）
- [x] #2 viewer-main.js の _escapeHtml が撤去され viewer.js の escapeHtml に一本化される
- [x] #3 差分マーカーのグリフ決定が 1 箇所になる
- [x] #4 effectiveZoom が撤去され呼び出し側が値を直接使う（または実体のある変換になる）
- [x] #5 ペーストボード書き込みと相対パス算出が共通化され、サイドバーとウィンドウのメニューで同じ結果になる
- [x] #6 既存の Node テストと swift test が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-432.3（viewer の JS のモジュール分割）で #2 と #3 を解消した。#2: DOM を使う _escapeHtml を撤去し encoding.js の純粋 escapeHtml へ一本化（呼び出しは _renderMmd の 1 箇所のみだった）。#3: 差分マーカーのグリフ決定を diff-html.js の diffMarkerGlyph へ集約し、インライン表示と左右分割が同じ 1 箇所を通るようにした。#1（_sourceLanguage の複製）は起票後に既に解消されており、現在の renderers.js の _renderSource は _sourceLanguage を呼んでいる。

残るのは #4 と #5。
- #4（effectiveZoom の恒等関数、現在は viewer-src/zoom.js）: 432.3 では撤去しなかった。重複した判定ではなく無意味な間接参照であり、撤去すると viewer.test.js の effectiveZoom テスト 2 ケースが消えるため、「既存テストのケース数が減っていない」という 432.3 の受け入れ条件と衝突する。このタスクで撤去する場合は、テストも一緒に消える前提で進めること。
- #5（writeToPasteboard の重複、Swift 側）: 未着手。

## #4 effectiveZoom の撤去

`viewer-src/zoom.js` の恒等関数 `effectiveZoom` を撤去し、6 箇所の呼び出しを値の直接使用に置き換えた（diagramScrollHeight の viewportCap、_mmdApplyZoom の width/height/zoom、_mmdFitImage）。export 一覧からも外した。起票時の想定どおり `viewer.test.js` の effectiveZoom テスト 2 ケースは一緒に消えている（jest 417 → 415）。TASK-432.3 の「ケース数を減らさない」条件は当該タスク内の話なので、本タスクで撤去してよいと Notes に記録済みだった前提に従った。

## #5 ペーストボード書き込みと相対パス算出の共通化

起票時の `ViewerWindowController.writeToPasteboard` は `ReferenceMenuPresenter` へ移動していた。実装時に**設計上の欠陥を実測で確認**した: presenter に渡していた基準は `baseURL: { self?.fileURL }`、すなわち**表示中ファイルの URL**（ディレクトリではない）。`PathRelativizer.relativePath(of:relativeTo:)` は base がファイルパスだと `starts(with:)` がまず成立せず絶対パスへフォールバックするため、本文のパス参照メニューの「相対パスをコピー」は実質いつも絶対パスを書き込んでいた。サイドバー側は `baseDirectory?.url ?? rootDirectory` 基準の相対パスで、2 つのメニューは実際に食い違っていた。

対応:
- `befold/App/Pasteboard.swift` を新設し、`writeString` / `writeFileReference` に clearContents + 書き込みを集約（FileListView の copyPath / copyFileReference、presenter の copyName / copyRelativePath の 4 経路がここを通る）。
- 相対パスの規則を `FileListModel.relativePathForCopy(_:)` の 1 箇所に置いた（FileListView から移動）。
- `ReferenceMenuPresenter` は**基準ディレクトリではなく算出済み文字列**を受け取る形に変えた（`relativePathForCopy: (URL) -> String?`）。基準を渡す形が残っていると同じ取り違えが再発するため、渡せる形自体を無くしている。
- `ViewerWindowController` は `fileListModel.relativePathForCopy` をそのまま渡す。

担保: `RelativePathCopyConsistencyTests` を追加し、参照メニュー経路とサイドバー経路が同じ文字列を返すことを baseDirectory 解決済み／未解決の 2 ケースで検証。**配線を壊すと実際に落ちることを実行して確認済み**（closure を別実装に差し替えると 2 ケースとも失敗）。

## #6 検証

- `swift test` → 1433 tests / 213 suites passed（新規 2 ケース分の増加）
- `npx jest` → 415 tests passed（effectiveZoom の 2 ケース削除分の減少）
- `npm run lint:viewer` / `typecheck:viewer` / `check:viewer-cycles`（循環なし・26 モジュール）いずれも通過
- `npm run build:viewer` で viewer-bundle.js を再生成しコミットに含めた
- swiftformat lint ゼロ件、変更した Swift ファイルの swiftlint 指摘ゼロ件

型グループのラチェット（scripts/check-type-group-size.sh --check）が FileListModel の +6 行で落ちたため、コメントを圧縮したうえでベースラインを更新した（484 → 490）。増加分は relativePathForCopy を FileListView から移した分で、移動元は 433 → 420 行と減っており 2 グループの合算では -7 行。ViewerWindowController は配線 1 行の置換のみで 855 行のまま据え置いた（最大グループを増やさないため、追加していた説明コメントを外した）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
残っていた #4 と #5 を解消した。#4: 恒等関数 effectiveZoom を撤去し呼び出し 6 箇所を値の直接使用にした（対応する jest 2 ケースも削除）。#5: クリップボード書き込みを Pasteboard へ、相対パスの規則を FileListModel.relativePathForCopy へ集約し、ReferenceMenuPresenter は算出済み文字列を受け取る形に変えた。実装中に、参照メニューが基準に表示中ファイルの URL を渡していて相対化が常に失敗していた（=サイドバーと結果が食い違っていた）ことを確認し、これも同時に解消した。RelativePathCopyConsistencyTests が 2 経路の一致を担保する（配線を壊すと落ちることを確認済み）。swift test 1433 passed / jest 415 passed。
<!-- SECTION:FINAL_SUMMARY:END -->
