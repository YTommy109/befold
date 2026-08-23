---
id: TASK-485.4
title: ソースコード表示で関数定義へジャンプできるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 13:18'
updated_date: '2026-08-23 16:38'
labels: []
milestone: m-6
dependencies:
  - TASK-485.17
parent_task_id: TASK-485
priority: medium
type: feature
ordinal: 715000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

4 つの対象のうち**最も不確実性が高い**。ソース表示の DOM は
`table.code-table` の `tr`（`viewer-src/code-html.js:128 buildLineNumberRows`）で、
行という単位はあるが「この行は関数定義である」という意味情報は持っていない。
hljs のハイライト結果（`highlightCode` :17、`reflowSpanBalancedLines` :35）から
`span.hljs-function` / `span.hljs-title` 等のトークンを拾うか、行テキストへ
言語別の正規表現をかけるかのどちらかになる。

さらに `StringChunkReader`（`BefoldKit/StringChunkReader.swift:38`、1000 行 / 1MB 単位）で
段階読み込みされるため、**未読み込み範囲の関数定義は DOM に存在しない**。
既存の検索も同じ制約を持ち、「表示範囲内」ラベルで明示している
（`find.js:239` / `ViewerBridge.truncatedScript` :213）。同じ方針を踏襲する。

## 論点（`/review-design` で扱うこと）

- **検出方式を決める。** hljs トークン方式は言語ごとの語彙差に弱く、正規表現方式は
  多言語分の規則を抱えることになる。どちらを採るか、対応言語を絞るかを先に決める
  （まず Swift / JS / TS / Python など数言語に限定し、非対応言語では
  この機能を無効化する、という縮小版も選択肢）
- **偽陽性の扱い。** 呼び出しと定義の区別、コメント・文字列内の一致
- 総数が「読み込み済み範囲の数」でしかないことを、どうユーザーに見せるか
- ジャンプ先の表示（関数名を出すか、n/N だけか）

## 注意

前段の 3 タスクより不確実性が高いため、**着手時に方式を決めてから実装する**。
方式の決定は不可逆な設計判断になりうるので、必要なら ADR を残すこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 対応すると決めた言語で、関数定義へ前後移動できる
- [x] #2 非対応言語では機能が無効であることが操作前に分かる（メニューが無効など）
- [x] #3 読み込み済み範囲だけを数えていることがユーザーに伝わる
- [x] #4 コメント・文字列内の紛らわしい行を定義と誤検出しないことをテストで示している
- [x] #5 検出方式の選定理由が Implementation Notes または ADR に残っている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 方式（/review-design の結論）

二役分離。「この行は定義か」= 言語別の行テキスト正規表現、「その行は本当にコードか」= hljs のスパン（.hljs-comment / .hljs-string）。

- 除外を自前の状態持ち回り（ATX_HEADING + CODE_FENCE 方式）で書かない。4 言語へ広げるとブロックコメント・生文字列・ヒアドキュメント・テンプレートリテラルの規則を抱え、TASK-316 と同型の穴になる
- 実測: reflowSpanBalancedLines が各行を reopen + line + close で組み直す（code-html.ts:83）ため、複数行コメント/文字列の途中の行も自分の td.line-content 内に hljs-comment / hljs-string を持つ
- hljs トークンは「定義である」ことの判定には使わない。実測で JS/TS は呼び出し側にも span.hljs-title.function_ が付く
- 対応言語 v1 = swift / typescript / javascript / python

## 手順

1. bar-mode.ts の列挙を 1 箇所へ畳む（currentMode() の kind === 'heading' || kind === 'changeBlock' を MODES.includes() へ）
2. viewer-src に functionDefinitionJumpProvider を追加。行あたりの正規表現は言語ごとに結合した 1 本。ignoresTruncation は付けない。isSelectionEmpty も実装しない
3. init.ts へ register を 1 行、bar-mode.ts の MODES / MODE_BUTTON_IDS、viewer.html のセグメントボタン
4. Swift: DocumentJumpKind に case 追加（tag 3）、FunctionJumpLanguages.supported、ViewerCapabilities に canJumpToFunctionDefinition = canJump && showsCodeContent && !showsDiff && 対応言語（デフォルト引数は付けない）、ViewerCapabilitiesFactory から FileType(url:).codeLanguage を渡す
5. Localizable.xcstrings に menu.edit.jumpToFunctionDefinition（既存キーの隣へ挿入。ソートし直さない）
6. 契約テスト: バンドルから言語集合をパースして FunctionJumpLanguages.supported と突き合わせる（ViewerJumpLevelContractTests と同じ手口）
7. jest: 誤検出テストは実 hljs 出力に対して書く（手書きダミー HTML にしない）
8. ADR を残す（hljs を字句状態の真実の源として使う判断は、今後の言語追加を拘束するため）

## 該当しないチェック項目

- 項目 5（ライフサイクル）: 常駐化もキャッシュ化もせず、既存の rebuild の呼び出しに乗るだけ
- 項目 8（非同期の世代管理）: 非同期取得を伴わない。列挙は同期で DOM から行う

## 別タスクへ切り出す

- MainMenuBuilder の分割（377/400 行）
- 文書内ジャンプのキー等価の割り当て
- 対応言語の拡張（go / rust / java / kotlin 等）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 検出方式の選定（AC #5 / ADR 0009）

**行テキストの言語別正規表現で「定義か」を決め、highlight.js のスパンで「本当にコードか」を決める**二役分離を採った。理由と実測は `backlog/decisions/decision-9` に記録した。要点:

- hljs トークン（`span.hljs-title.function_`）を定義の判定に使わない。**実測で JS/TS は呼び出し側にも同じクラスが付く**（`foo(1)` / `obj.method(2)` / `compute()`）。Swift / Python では定義にしか付かないため、言語ごとに意味の変わる判定を共通経路に置くことになる
- コメント・文字列の除外を自前で持ち回らない。`reflowSpanBalancedLines`（`viewer-src/code-html.ts:83`）が各行を `reopen + line + close` で組み直すため、**複数行コメント／文字列の途中の行も自分の `td.line-content` 内に `hljs-comment` / `hljs-string` を持つ**。node で hljs を直接呼んで確認した
- 対応言語は swift / python / javascript / typescript の 4 つ。JS/TS のメソッド短縮記法は `if (x) {` と行の形が同じで除外語彙が要るため v1 の対象外（TASK-485.23 へ切り出し）

## /review-design の結果と反映

実装前に `/review-design` を 1 回回し、7 件を設計に反映した。

1. **項目 3（兄弟判断の全列挙）**: Swift 側は `DocumentJumpKind.allCases` と exhaustive switch で自動追随するのに、JS 側の `bar-mode.ts` だけが列挙式だった（`MODES` と `currentMode()` の `kind === 'heading' || kind === 'changeBlock'` の 2 箇所）。**`currentMode()` を `MODES` 経由へ畳んで列挙を 1 箇所にした**
2. **項目 1（判定の真実の源）**: 上記のとおり hljs の字句状態へ寄せた（TASK-316 と同型の穴を避ける）
3. **項目 1（同じ形がデータ側に現れないか）**: hljs トークンは除外にだけ使う
4. **項目 2（既存の不変条件）**: `showsCodeContent` は差分表示中も true（`ViewerStore.swift:170` の `isSourceMode` 経由）。`!showsDiff` を落とすと**差分表示中にメニューが有効のまま 0 件**になるため条件に含めた
5. **項目 3 + 9（消費経路 / 粒度を守らせるもの）**: 対応言語の集合が Swift と JS の 2 箇所に生まれるため、`ViewerFunctionJumpLanguageContractTests` を同じタスク内で用意した（`ViewerJumpLevelContractTests` と同じ手口）
6. **項目 9（デフォルト引数の禁止）**: `ViewerCapabilities` の `codeLanguage` にデフォルト値を付けなかった。結果、既存の全呼び出し元がコンパイルエラーで露出した（意図どおり）
7. **項目 6（高頻度経路のコスト）**: 行あたりの正規表現を言語ごとに 1 本へ結合。さらに**素のテキストで足切りしてから候補行だけコメント・文字列を除いて再判定**する形にし、全行に対する DOM 走査コストを候補行だけに寄せた

該当しなかった項目: 5（常駐化・キャッシュ化をせず既存 rebuild に乗るだけ）、8（非同期取得を伴わない）。項目 10 は下記。

## 型グループの行数（項目 10）

閾値 400（`scripts/check-type-group-size.sh:29`）。増分は次のとおりで、`MainMenuBuilder`（377 行、残り 23）は **allCases ループのため増分 0 行**だった。`ViewerMenuValidator` / `WebViewCommandController` も同様に自動追随。実行後も `check-type-group-size.sh` は exit 0。ただし MainMenuBuilder の余裕が小さいことは変わらないため TASK-547 を起票した。

## 既存の予告との関係

`docs/dev/native-app-design.md` に「**種別では capability を閉じない**（`canJump` に fileType を持ち込むと TASK-485.4 が来た時点で条件が反転する）」という予告があった。これは守った——`canJump` に言語を持ち込まず、種類ごとの述語 `canJumpToFunctionDefinition` を足した。文書側もその形へ書き換えた。

## 想定外だったこと

`WebViewCommandControllerTests` の「使える種類の同期は DocumentJumpKind の全種類を検査する」が落ちた。**1 つの能力状態では全種類がそろわなくなった**ため（変更ブロックは差分表示中のみ、定義は逆に差分表示でないときのみ）。テストの意図（列挙を書き足す実装に変わったら落ちる）を保つため、差分表示中と非差分表示の**和**が `allCases` に一致する形へ書き換えた。

## 検証（実測）

- `swift test` → **1706 tests / 271 suites すべて passed**
- `npx jest` → **579 tests / 13 suites すべて passed**（新規 `viewer-main-jump-function.test.js` 13 件を含む）
- **決めた条件が破れたら落ちることを確認した**（通っただけでは何も検証していないため）:
  - `!showsDiff` を外す → 「定義へのジャンプは差分表示中と非ソース表示中は不可」が失敗
  - `FunctionJumpLanguages.supports(codeLanguage)` を `true` に置換 → 「定義へのジャンプは対応言語のソース表示中だけ可能」が 2 件失敗
  - どちらも復元後に再度 passed
- swiftlint: **新規違反ゼロ**（`/swiftlint-baseline` の手順。origin/main を git archive で別ディレクトリへ展開して比較。main 54 件 / 作業ツリー 54 件、raw diff も空）
- swiftformat（fix モード）→ 整形差分なし
- `npm run lint`（oxlint --type-aware）→ 0 件。初回は `no-unsafe-type-assertion` が 1 件出たので、`cloneNode(...) as HTMLElement` をやめて子ノード走査に変えた（アサーションも DOM 複製も不要になり、行数ぶんの clone を避けられた）
- `npm run format`（oxfmt）→ 適用済み
- `markdownlint-cli2` → 78 files, 0 issues
- `scripts/check-doc-symbols.sh` → exit 0
- `scripts/check-type-group-size.sh` → exit 0
- `xcodegen generate` 実行済み（新規ファイル 3 本を追加したため）

## 未検証

**GUI での実機確認は行っていない。** メニュー項目の表示・グレーアウトは `ViewerMenuValidatorTests` で、バーのセグメント表示は `viewer-main-bar-mode.test.js` で測っているが、実際の macOS アプリ上での見え方（「定義」セグメントの幅・4 つ並んだときのバーのレイアウト）は確認していない。バーのセグメントが 3 つから 4 つに増えるため、**ここは目視の確認が要る**。

## バーのレイアウト（未検証だった点の解消）

セグメントが 3 → 4 に増えることによる横幅の懸念は、**同時に見えるのは最大 3 つ**であることが分かったので解消した。変更ブロック（差分表示中のみ）と定義（差分表示でないときのみ）が排他なので、見えるのは常に「検索 + 見出し + どちらか一方」になる。今までと同じ数。

この排他は `ViewerCapabilities` の条件から導かれるだけで担保が無かったため、`ViewerCapabilitiesTests` に「変更ブロックと定義のジャンプは同時には使えない」を足した（破れると 4 つ並んでバーが広がるため）。

CSS 側も固定幅を持たない（`.mmd-find-bar` は `flex-direction: column; align-items: stretch`、`.mmd-bar-modes` は `justify-content: flex-end; gap: 2px`、セグメントは `width: auto; white-space: nowrap`）ので、仮に増えても折り返しや切れは起きない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ソースコード表示で関数・型の定義行へ前後移動できるようにした（DocumentJumpKind の 3 つ目の種類 functionDefinition）。

検出方式は二役分離: 「この行は定義か」を言語別の行テキスト正規表現で決め、「その行は本当にコードか」を highlight.js のスパン（.hljs-comment / .hljs-string）で決める。コメント・文字列の除外を自前で持ち回らないのは、reflowSpanBalancedLines が行ごとに span を開き直すため複数行コメント／文字列の途中の行も自分の td 内に印を持つから。逆に span.hljs-title.function_ は定義の判定に使わない（JS/TS は呼び出し側にも同じクラスが付くことを実測）。選定理由は ADR 0009 に記録した。

対応言語は swift / python / javascript / typescript の 4 つ。非対応言語ではメニュー項目が押す前からグレーアウトする（ViewerCapabilities.canJumpToFunctionDefinition、条件は差分表示中でないソース表示 かつ 対応言語）。言語集合が Swift と JS の 2 箇所にあるため ViewerFunctionJumpLanguageContractTests で結んだ。段階読み込み中は「表示範囲内」ラベルを出す（差分と違い appendChunk で実際に追記が起きるため ignoresTruncation は付けない）。

実装前に /review-design を 1 回回し 7 件を設計へ反映。特に bar-mode.ts のモード列挙が 2 箇所に分かれていた（Swift 側は allCases で自動追随するのに JS 側だけ取り残される形）のを MODES の 1 箇所へ畳んだ。

検証: swift test 1706 件 / jest 579 件すべて passed。決めた 2 条件（!showsDiff、言語ゲート）はそれぞれ外すと該当テストが落ちることを確認済み。swiftlint 新規違反ゼロ（origin/main を git archive で展開して比較、main 54 / head 54、raw diff も空）。oxlint 0 件、oxfmt・swiftformat 適用済み、markdownlint 0 issues、check-doc-symbols / check-type-group-size とも exit 0。誤検出テストは手書きダミー HTML ではなく main.render() を通した実 highlight.js 出力に対して書いた。

未着手として切り出したもの: TASK-485.23（JS/TS のクラスメソッド短縮記法）、TASK-485.24（対応言語の拡張）、TASK-485.25（キー等価の割り当て）、TASK-547（MainMenuBuilder の分割）。
<!-- SECTION:FINAL_SUMMARY:END -->
