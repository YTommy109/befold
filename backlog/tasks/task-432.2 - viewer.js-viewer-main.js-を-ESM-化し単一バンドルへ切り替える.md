---
id: TASK-432.2
title: viewer.js / viewer-main.js を ESM 化し単一バンドルへ切り替える
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 12:56'
updated_date: '2026-08-11 13:35'
labels: []
dependencies:
  - TASK-432.1
parent_task_id: TASK-432
priority: medium
type: chore
ordinal: 112200
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
- [x] #1 viewer.js / viewer-main.js が import / export で依存を表現している
- [x] #2 viewer.html が単一のバンドル成果物を読み込む形になっている
- [x] #3 ESM 化の前に未定義参照を機械検出する仕組みが有効になっており、変換後の検出結果がゼロである
- [x] #4 既存の 370 ケースが通る（ケース数が減っていない）
- [x] #5 ViewerBridgeContractTests が成果物を見る形に向け直され、通る
- [x] #6 mermaid.min.js がバンドルへ取り込まれておらず、遅延ロードのまま動作する
- [x] #7 CSP が変更されていない
- [x] #8 本体アプリと QuickLook 拡張の双方で表示が変わらないことを確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. no-undef を機械検出できる状態を先に作る（ESLint flat config + npm run lint:viewer）
2. viewer.js / viewer-main.js を viewer-src/ へ git mv し、末尾の CommonJS 境界を export へ置換する
3. eslint の no-undef 出力を列挙器として使い、viewer-main.js の裸参照を import へ移す
4. バンドルのエントリ index.js で公開関数を globalThis へ載せ直し（expose.js）、_mmdInit() を呼ぶ
5. viewer.html をベンダー3本 → viewer-bundle.js の読み込みへ差し替える
6. Jest ハーネスを esbuild + window.eval 方式へ作り替え、417 ケースを維持する
7. ViewerBridgeContractTests を viewer-bundle.js を読む形へ向け直す
8. Package.swift / project.yml / CI / スモークスクリプト / ドキュメントを追随させる
9. swift build・xcodebuild・swift test・webview-smoke で検証する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決めたこととその理由

- **ベンダーはバンドルに含めない**。markdown-it / highlight.js / DOMPurify は viewer.html が classic script で先に読み、バンドルからはグローバルとして参照する（eslint 側で readonly グローバルとして宣言）。本サブタスクの趣旨が「振る舞いとファイル構成を保ったまま依存の表現方法だけを変える」ことであり、同梱ベンダーの出所（THIRD_PARTY_LICENSES の対象）を npm 版へ差し替える判断を巻き込まないため。mermaid は従来どおり描画時の動的 script 挿入で遅延ロード（viewer-main.js の 3.2MB 遅延ロードの設計意図をそのまま維持）。
- **未定義参照の検出は ESLint の no-undef**（tsc --checkJs ではなく）。目的が「import の付け忘れ検出」に限定されており、型注釈のない既存コードへ型検査を入れると本題と無関係な指摘が大量に出る。実測: 変換前に走らせると viewer-main.js に 68 件（うち 43 識別子が viewer.js 由来）、viewer.js に 0 件。この 43 件をそのまま import リストにした。**viewer.js → viewer-main.js の逆参照は 0 件で循環なし**。変換後は 0 件。
- **公開関数のグローバル露出は expose.js の exposeGlobals() に一本化**。ESM 化前は classic script のトップレベル関数宣言が暗黙にグローバル化しており、Swift の  はこれに依存していた（コード上 window.X = の明示代入は 1 箇所も無かった）。IIFE ではこれが失われるため明示的に載せ直す。個別列挙ではなく名前空間オブジェクトの反復にしたのは、公開関数を足したときの追記漏れで実行時まで気づけない形を作らないため（export した時点で載る）。本番エントリとテストハーネスの両方が同じ exposeGlobals を通るので「テストでは見えるが本番では無い」ずれも生じない。
- **Jest ハーネスは esbuild + jsdom の window.eval**。当初 babel-jest で require する形を試したが、モジュールが window / document を裸参照するため Node の globalThis へ結び付けるしかなく、1 テストが 2 つの window を扱う場面（viewer-main-source-append.test.js の md/code 比較）で後から読み込んだ側に全インスタンスが引きずられた（実測: 15 件失敗）。window.eval なら評価スコープが window ごとに分かれ、ブラウザと同じ独立性が保てる。ハーネスはコミット済み成果物ではなくソースから毎回バンドルするため、ソース編集直後もビルドを挟まずに現在の実装を見る。
- **契約テストは成果物（viewer-bundle.js）を読む**。esbuild の出力に合わせて 2 点を直した。(1) 文字列リテラルが二重引用符へ正規化されるため照合トークンを合わせた。(2) `href: href` が短縮記法へ畳まれるため、ペイロードキー抽出を `key:` 限定の正規表現から「, 区切り＋: の前が識別子」方式へ変えた。
- **ズーム定数の照合を値ベースへ**。esbuild は `2.0` を `2` へ正規化するため `var ZOOM_MAX = \(ZoomStore.maxZoom);` の文字列一致が壊れた。表記に合わせて Int() を挟む小細工は閾値の型が変わるたびに壊れるので、jsNumber(named:in:) で数値として取り出して比較する形にした（ZOOM_DEFAULT の既存の Int() 回避策もこれで不要になった）。
- **webview-smoke.swift の globals 判定を変更**。`typeof md`（markdown-it インスタンス）を見ていたが、これは viewer-main.js の module 内部変数でありバンドル化で内部へ閉じた（意図した結果）。代わりに公開関数 `typeof render` を見る。md が初期化されることは同スクリプトの .md 描画確認が担保する。

## 検証

- `npx jest`: 417 passed / 6 suites（移行前と同数）
- `npm run lint:viewer`（eslint no-undef）: 0 件
- `swift build`: Build complete
- `swift test`: 1415 tests / 208 suites すべて pass（ViewerBridgeContractTests 10 件を含む）
- `xcodebuild build -scheme befold`: BUILD SUCCEEDED。生成された .app の BefoldKit.framework Resources に viewer-bundle.js と viewer.html のみ（viewer.js / viewer-main.js は消えた）
- `swift scripts/webview-smoke.swift`: PASS（CSP 下でのスクリプト稼働・mmd/md 描画・外部画像/data: iframe ブロック・PDF blob 表示）
- QuickLook 拡張は自前の viewer リソースを持たず `@executable_path/../../../../Frameworks` の BefoldKit.framework を見る構成（otool -l で確認）ため、本体アプリと同一の成果物を読む

（補足）上の 3 点目で消えた引用: Swift 側の呼び出し形は `evaluateJavaScript` に `_mmdZoomIn()` のような裸の呼び出し文字列を渡す形（ViewerBridge.PlainFunction.callScript）。

AC#8: Debug ビルドを /Applications へ入れ替えて appex を登録し直し、本体アプリ（.md / .mmd / .csv）と qlmanage -p による QuickLook プレビュー（.mmd / .md）をユーザーが目視確認し、いずれも従来どおりであることを確認した。確認後、退避しておいた元のインストール版（1.12.3-dev.6）へ戻した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer.js / viewer-main.js を BefoldApp/viewer-src/ へ移して ESM 化し、esbuild の単一成果物 viewer-bundle.js を viewer.html が読む形へ切り替えた。責務の分割は行っていない。付け忘れが実行時まで表面化しない裸のグローバル参照の移行は、先に ESLint の no-undef を有効化してその出力を列挙器として使い、変換前 68 件（43 識別子が viewer.js 由来・循環なし）を 0 件にした。IIFE 化で失われる暗黙のグローバルは expose.js に一本化して本番エントリとテストハーネスの双方が同じ経路を通る形にし、Jest ハーネスは esbuild + jsdom の window.eval 方式へ作り替えて 417 ケースを維持した。ViewerBridgeContractTests は成果物を読む形へ向け直し、esbuild の正規化（引用符・短縮記法・数値表記）に依存しない照合へ変えた。検証: jest 417 pass / lint:viewer 0 件 / check:viewer-bundle exit 0 / swift build / swift test 1415 pass / xcodebuild BUILD SUCCEEDED / webview-smoke PASS / 本体アプリと QuickLook の目視確認。
<!-- SECTION:FINAL_SUMMARY:END -->
