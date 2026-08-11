---
id: TASK-432.3
title: viewer-main を責務ごとのモジュールへ分割する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-10 12:57'
updated_date: '2026-08-11 14:13'
labels: []
dependencies:
  - TASK-432.2
parent_task_id: TASK-432
priority: medium
type: chore
ordinal: 112300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-420 を引き継ぐサブタスク（TASK-420 はこちらへ統合してアーカイブ済み）。モジュール境界を得た後に、責務単位でファイルを分ける。

## TASK-420 から引き継ぐ内容

`viewer-main.js`（1,873 行）はモジュール境界を持たないまま次をすべて所有している: ズーム、キーボードスクロール、参照クリック、パス参照の注釈と非同期解決、ダイアグラム単位のズーム、mermaid のロード、markdown-it の設定、検索コントローラ一式、document / scroll / doc-path / chunk-tail / pdf-blob の各状態、7 つの型別レンダラ、チャンク追記、初期化。

ファイル内のセクション区切りコメントが現状の関心の一覧になっている: `:22` Zoom、`:215` リンク・パス参照クリック、`:302` 表示時のパス参照解決、`:450` Diagram Zoom、`:568` Mermaid、`:640` Markdown-it、`:685` Find、`:1102` Render、`:1538` 型別 DOM ビルダー、`:1800` 初期化。

## TASK-420 から変わった点

TASK-420 の受け入れ条件 #3 は「viewer.html からの読み込み順が壊れず」だった。TASK-432.2 の完了後は読み込み順という暗黙の契約自体が消えているため、この条件は不要になる。代わりに、依存が import で表現され循環していないことを見る。

## 分割の判断基準

`viewer.js` と `viewer-main.js` の現在の境界（純粋ロジック / DOM）は**責務ではなくテスト可能性**で引かれており、同じ関心の 2 つの枝が離れて置かれて実際に乖離した（TASK-414）。分割後は関心ごとに 1 モジュールとし、その中で純粋な部分と DOM に触る部分が同居してよい。テスト可能性はモジュール境界ではなく import で担保する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 viewer-main が責務単位のモジュールへ分割されている（少なくとも 検索 / 参照解決 / ズーム / レンダラ群 / 初期化 が分かれる）
- [x] #2 同じ関心の判定が 2 箇所に残っていない
- [x] #3 モジュール間の依存が import で表現され、循環が無い
- [x] #4 各モジュールが何を担うかを 1 行で言える
- [x] #5 既存テストが通り、ケース数が減っていない
- [ ] #6 本体アプリと QuickLook 拡張の双方で表示が変わらないことを確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. viewer.js / viewer-main.js を解体し、関心ごとの 19 モジュールへ再配置する（純粋関数と DOM 操作を同居させる）: bridge / doc-path / view-options / document-state / color-scheme / fonts / encoding / code-html / diff-html / csv-html / zoom / scroll / keyboard / find / path-refs / reference-clicks / markdown / mermaid / renderers / render / truncation / init
2. 公開面は barrel（viewer-src/main.js）1 本に集約し、index.js とテストハーネスの双方がそこだけを見る形にする
3. 依存が一方向になるよう境界を切る: bridge/doc-path/view-options/document-state/color-scheme を葉に置き、render を頂点にする。カラースキーム変更時の再描画は color-scheme のコールバック登録で mermaid→render の逆流を作らない
4. render が実際に描いた形（_mmdRenderedAs）の書き手を render 1 箇所に閉じる（_renderSource が描いた形を返す）
5. AC#2 の重複解消: _escapeHtml（DOM 版）を純粋 escapeHtml へ一本化 / 差分マーカーのグリフ決定を 1 箇所へ / 恒等関数 effectiveZoom を撤去（TASK-422 の #2〜#4 に相当）
6. テストは barrel を参照する形へ向け直し、ケース数を維持する（viewer/main の 2 分割が消えるため harness の返り値も 1 本にする）
7. eslint no-undef 0 件 / jest 417 / build:viewer で成果物更新 / swift build / swift test / xcodebuild / webview-smoke で検証し、本体アプリと QuickLook を目視確認する

8. /review-design の結果を反映する:
   (A) _mmdRenderedAs は分岐前の記録を残し、source 分岐だけが戻り値で上書きする（markdown-it 未ロード時の早期 return で記録が飛ぶのを防ぐ）。モジュール変数は export せず書き手を render.js の 1 箇所に閉じる
   (B) 循環 import を esbuild の metafile から検出する check:viewer-cycles を追加し CI へ並べる（AC#3 を「破れたら落ちる」形にする。scroll.js が評価時に別モジュールのトップレベル値を読むため実害がある）
   (C) exposeGlobals の引数を barrel 1 つに固定し、個別モジュールを混ぜて渡せない形にする
   (D) color-scheme.js が matchMedia を遅延生成する prefersDark() を持ち、_mmdDarkQuery が null である期間自体を無くす
9. 未確認の前提: esbuild のローカル名衝突による改名が ViewerBridgeContractTests の文字列照合を壊さないか。build:viewer 後の swift test --filter ViewerBridgeContract で確認する。破れたら照合を緩めず衝突側のローカル名を改名する

10. effectiveZoom（TASK-422 の #4）はこのタスクでは撤去しない。重複した判定ではなく無意味な間接参照であり AC#2 の対象外な一方、撤去すると viewer.test.js の 2 ケースが消えて AC#5（ケース数が減っていない）と衝突する。TASK-422 に残す。AC#2 として扱うのは _escapeHtml の重複（DOM 版 vs 純粋版）と差分マーカーのグリフ決定の 2 件。実測: 移行前のベースラインは jest 417 passed / 6 suites
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決めたこととその理由

- **viewer.js も一緒に解体した。** Description の「分割後は関心ごとに 1 モジュールとし、その中で純粋な部分と DOM に触る部分が同居してよい」に従い、viewer-main.js だけを割るのではなく viewer.js の純粋関数も関心側へ配った（ズーム定数は zoom.js、検索の正規表現組み立ては find.js、行番号 HTML は code-html.js、といった具合）。viewer-main.js だけを分けると「純粋 / DOM」の境界が残り、TASK-414 の乖離を生んだ形がそのまま残る。
- **公開面は barrel（main.js）1 本。** 本番エントリ（index.js）と Jest ハーネスの双方がここだけを見る。加えて exposeGlobals の可変長引数をやめて barrel 1 つだけを受ける形にした（個別モジュールを混ぜて渡せると、本番とテストでグローバルに載る集合がずれても落ちない）。barrel は export * にしてある。モジュール間共有のための export も公開面に載るが、分割前も viewer.js / viewer-main.js の全 export をそのままグローバルへ載せていたため露出量は実質変わらず、明示リストにすると二重管理になる。実測: 旧 2 ファイルの export 集合と新 barrel の集合を突き合わせ、**消えた名前は 0 件**（増えたのは内部共有用の 39 件）。
- **描いた形の記録（_mmdRenderedAs）は分岐前の代入を残した。** 当初案の「_renderSource の戻り値だけで決める」は、markdown-it 未ロードで打ち切る経路（_renderMarkdown が false を返して return）で記録が飛び、appendChunk が前回の戦略で追記する形になる。分岐前に renderShape の値を入れ、差分を組み上げたときだけ _renderSource の戻り値で上書きする。書き手は render.js の 1 箇所で、変数は export しない。
- **循環 import は検出器を足した。** AC#3 を「破れたら落ちる」形にするため npm run check:viewer-cycles（esbuild の metafile から後退辺を探す）を追加し CI へ並べた。循環に実害があるのは、scroll.js が評価時に doc-path.js のトップレベル値 _mmdDocPath を読む形が実在するため（循環すると undefined を掴む）。検出器自体の動作は bridge.js に一時的な逆向き import を入れて確認した（find.js -> bridge.js -> find.js を検出）。
- **カラースキームは color-scheme.js が遅延生成する prefersDark() にした。** 分割前は _mmdDarkQuery が初期化まで null で、「代入前に mermaid を描画する経路はない」という暗黙の前提に乗っていた。モジュールをまたぐとこの前提が見えなくなるため、null である期間自体を無くした。再描画の配線（mermaid の再初期化 + 直近内容の再描画）は init.js に置き、mermaid -> render の逆流を作らない。
- **effectiveZoom（TASK-422 #4）は撤去しない。** 重複した判定ではなく無意味な間接参照であり AC#2 の対象外な一方、撤去すると viewer.test.js の 2 ケースが消えて AC#5 と衝突する。TASK-422 に残した。
- **テストファイル名は据え置いた。** viewer-main*.test.js は分割前のファイル名に由来するが、中身の区切りは新しいモジュール境界と 1 対 1 ではないため、名前を変えるより先頭コメントで守備範囲を書き直した。

## 検証

- npx jest: 417 passed / 6 suites（移行前と同数。ベースラインも 417）
- npm run lint:viewer（eslint no-undef）: 0 件
- npm run check:viewer-cycles: 循環なし（25 モジュール）
- npm run check:viewer-bundle: 差分なし（exit 0）
- swift build: Build complete / swift test: 1415 tests / 208 suites すべて pass
- swift test --filter ViewerBridgeContract: 10 件 pass。**着手前に未確認としていた前提（esbuild のローカル名衝突による改名が成果物の文字列照合を壊さないか）はここで解消した**
- xcodebuild build -scheme befold: BUILD SUCCEEDED
- swift scripts/webview-smoke.swift: PASS（CSP 下でのスクリプト稼働・mmd/md 描画・外部画像/data: iframe ブロック・PDF blob 表示）
- markdownlint-cli2: 0 issues
- バンドルサイズ: 75.8K -> 78.5K（モジュール境界とコメントの増加分）

## 追随させたドキュメント

docs/dev/rules/product-code.md（JS 規約の「純粋ロジックは viewer.js へ」を「関心ごとに 1 モジュール・循環禁止」へ書き換え）/ docs/dev/rules/testing.md / docs/dev/viewer-rendering-dataflow.md / BefoldApp/viewer-src/README.md（モジュール一覧と 1 行責務）/ .claude/agents/vendored-deps-auditor.md / .claude/commands/check-vendored-deps.md / .claude/agents/security-reviewer.md / .claude/skills/review-architecture.md。ADR 0005 は決定時点の記録なので書き換えない。
<!-- SECTION:NOTES:END -->
