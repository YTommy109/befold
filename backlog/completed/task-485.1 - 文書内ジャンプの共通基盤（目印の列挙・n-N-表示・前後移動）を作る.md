---
id: TASK-485.1
title: 文書内ジャンプの共通基盤（目印の列挙・n/N 表示・前後移動）を作る
status: Done
assignee: []
created_date: '2026-08-14 13:17'
updated_date: '2026-08-17 09:40'
labels: []
milestone: m-6
dependencies:
  - TASK-510
parent_task_id: TASK-485
priority: medium
type: task
ordinal: 712000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

`viewer-src/find.js` は「マッチ列 + 現在位置 + n/N 表示 + 前後移動 + 現在位置ハイライト
+ scrollIntoView」を 1 つのクロージャに閉じ込めている（`_createFindController()` :39）。
見出し・差分・関数定義のジャンプは、**列挙の仕方だけが違って残りは同じ**。

そこで、目印（target）の列を返すプロバイダを受け取り、位置管理と UI を担う
共通コントローラを切り出す。find.js 自体をこの基盤へ載せ替えるかは設計判断
（載せ替えるなら既存の検索の挙動を変えないことを担保するテストが要る）。

## 設計上の論点（`/review-design` で扱うこと）

- 検索バーと**同じバーを使い回す**のか、別バーを出すのか。同時に開ける必要はあるか
- 目印の粒度が「要素」か「行（tr）」かで、ハイライトの当て方が変わる。`mark.mmd-find-match-current`
  は inline 要素前提で、行ハイライト用の CSS は現状無い（`style.css:627/632`）
- 再描画・チャンク追記への追従。`render.js:74 _mmdFindRefreshAfterRender()` と
  `find.js:349 setTruncated` が既にある。ここへ相乗りするか、同型の口を増やすか
- Swift 側のコマンドの持ち方。`ViewerBridge.PlainFunction`（:25-48）へ足す関数の数を
  対象ごとに 3 本ずつ増やすのか、対象を引数に取る 1 組にするのか
- キーバインドの割り当て（⌘F / ⌘G / ⇧⌘G は検索が使用済み。`MainMenuBuilder.swift:136-148`）
- 表示モードごとの可否判定は `ViewerCapabilities`（`befold/Viewer/ViewerCapabilities.swift:16,59`）
  に `canFind` の前例がある。同じ形で導出する

## 注意

`viewer-src/main.js` へ export すれば `expose.ts:21 exposeGlobals()` が自動で
window に載せる。Swift 側は `ViewerBridge` のテストが `function _mmdX()` の
定義トークン存在を検証している（:45）ので、追加関数も同じ規約に従うこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 目印の列挙を差し替えるだけで別種のジャンプが作れる形になっている
- [x] #2 現在位置と総数の表示、前後移動、現在位置のハイライトとスクロールが共通化されている
- [x] #3 再描画とチャンク追記のあとで目印の列が再構築される
- [x] #4 既存の検索窓の挙動（マッチ数・移動・ハイライト・truncated 表示）が変わっていないことをテストで担保している
- [x] #5 この基盤の上で少なくとも 1 種類の目印が動くところまで確認できている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
`/review-design` を 1 回実施し、指摘（項目 1〜7 で 15 件、項目 8〜10 で High 4 / Medium 3）を反映して確定した設計。

## 確定した決めごと

### J1. find.ts は載せ替えない。共有するのは純粋な部分だけ
find の複雑さの大半はテキストマッチと `<mark>` 挿入（find.ts:105-311）で、ジャンプには無い関心。
共有するのは (a) インデックス演算 3 関数（`nextMatchIndex`/`prevMatchIndex`/`keptMatchIndex`）と
(b) 件数ラベルの組み立てのみ。新モジュール `viewer-src/jump.ts` にコントローラを置く。

**`formatJumpCount(current, total, truncated, label)` の責務は「n/N と truncated ラベルの
組み立てだけ」に限定する。** `updateCount`(find.ts:322-326) が持つ「クエリ空 → `''`」
「`mmd-find-error` → `''`」の 2 分岐は呼び出し側に残す（引数で状態を渡さない）。

### J2. 目印は 1 要素とは限らない
`JumpTarget = { anchor: HTMLElement; highlight: HTMLElement[] }` とする。
差分の左右分割では 1 変更ブロックが左右 2 つの `tr` になる（style.css:354-369 の
`.diff-side-table` は入れ子テーブル）ため、`HTMLElement[]` で固定すると 485.3 で n/N が倍になる。
`JumpProvider = { id: string; collect(root: HTMLElement): JumpTarget[] }`。

### J3. バーの排他は 1 個の所有者で表す（破れない構造）
find の `isOpenFlag`(find.ts:168) の隣にもう 1 個フラグを置くと「両方開いている」が
型の上で表現可能になり、「同時に開かない」が doc コメントだけの決めごとになる。
**`null | 'find' | 'jump'` を持つ単一の所有者**を新設し、`find.isOpen()` はそこを見る形へ変える。
`keyboard.ts:66-73` の `resolveFindCloseKey(key, isFindOpen, …)` も
`resolveBarCloseKey(key, openBar, …)` へ一般化する（Escape の判定を 2 箇所に分けない）。

### J4. ハイライトとスクロールを分離する
`highlightCurrent` は必ず `scrollIntoView`(find.ts:337-345) する。ジャンプが同じ形で
再構築フックに乗ると、**バーを開いている間、チャンク追記のたびに読んでいる位置を奪う**
（`render.ts:298` の appendChunk 経路にはスクロール復元が無い）。
`moveTo(index, { scroll })` とし、再構築経路は `scroll: false`、`next`/`prev`/`open` のみ `true`。

### J5. `_mmdModeSwitch.consume()` はフック内で 1 回だけ
`consume()`(view-options.ts:8-20) は破壊的読み出し。`_mmdFindRefreshAfterRender`(render.ts:83-88)
が既に消費しているため、ジャンプ側で 2 回目を呼ぶと必ず false を受け取り、
モード切替時の先頭リセットがジャンプ側だけ効かない。**1 回消費した値を find と jump の
両方へ引数で渡す。**

### J6. 開始時の無効化を置く
再構築（着地時）だけでは、`render()` が `await _mmdRunMermaid`(render.ts:145) を挟む間、
**前の文書の n/N と current ハイライトが表示され続ける窓**ができる。
`_mmdScroll.beginRender()` と同じ位置に `invalidate()`（列を空にし `0/0` へ）を置く。
着地時は再構築し、位置は可能な限り維持する（find の `refresh` と同じ流儀。バーは閉じない）。

### J7. ゲートの露出点は `canJump` の導出 1 箇所に閉じる
`FeatureGate.isDocumentJumpEnabled` を `ViewerCapabilitiesFactory` から注入し、
`canJump` を導出する。メニュー（`ViewerMenuValidator`）と実行ガード
（`WebViewCommandController`）の両方が自動で塞がる＝破れない構造。
ADR 0002「条件は 1 箇所」および `ViewerCapabilities` の doc（:3-11）にも沿う。
導出は**事実だけ**で書く: `canJump = isDocumentJumpEnabled && onDocument && !isDirectHTMLMode`。
**目印 0 件は capability では表さない**（段階読み込み中・描画前でも同じ 0 件になり破れる）。
TASK-510 で書いた `FeatureGate` の doc コメント（露出点の記述）もこの形に直す。

### J8. 485.1 ではキー等価を付けない
⌃⌘G は既に「変更されたファイルのみ表示」が使用済み（`MainMenuBuilder+ViewMenu.swift:74-77`。
しかもそのコメントは「素の ⌘G / ⇧⌘G は検索と衝突するため control を重ねた」と書いている）。
加えて `site/src/lib/shortcuts.ts:38-52` のパーサは FeatureGate ガードを認識しないため、
キー等価を付けると **dev 限定機能が紹介サイトのショートカット表に載るか site テストが落ちる**。

実測で `parseCallChunk` は `keyEquivalent:` を持たない項目を `null` で捨てる
（`site/src/lib/shortcuts.ts:79-81`）ことを確認した。よって **485.1 ではメニュー項目のみを置き、
キー等価は付けない**。前後移動はバー内の Enter / ⇧Enter（検索バーと同じ形、find.ts:463-476）。
キーバインドの確定は安定稼働の判断と同時に行う（stable 昇格タスクの AC にする）。

### J9. `@objc` アクションは 1 本に畳む
`ViewerWindowController` 型グループは **869 行 / 恒久例外の上限 900**（残り 31 行）で、
`find(_:)`/`findNext(_:)`/`findPrevious(_:)` と同じ流儀で 4 本足すと
`scripts/check-type-group-size.sh --check` が CI で落ちる（例外の引き上げは規約違反）。
`selectDisplayMode(_:)` に前例のある **tag 方式で 1 本** `documentJump(_ sender: NSMenuItem)` に畳む。

### J10. Swift 側の入口の命名は既存契約に揃える
`_mmdJumpNextIfOpen` / `_mmdJumpPrevIfOpen`（`_mmdFindNextIfOpen` に倣う）。
引数を取る `_mmdJumpOpen(kind)` は `PlainFunction` に載せられない（契約テストが
素の `function name()` 宣言を要求する）ため `openFindScript` と同じ文字列定数とし、
**定義存在チェックを `ViewerBridgeTests` へ 1 本足す**（契約テストの網から外れるため）。

### J11. 局在化の経路を通す
検索バーは placeholder/title が viewer.html にハードコードで、実際の局在化は
`ViewerBridge.findStringsScript`(:302-313) の注入で上書きする方式。ジャンプバーにも
同型の `jumpStringsScript` と適用処理、`Localizable.xcstrings` へのキー追加が要る
（キー順にソートし直さず近縁キーの直後へ挿入する）。

### J12. 再構築は「開いているときだけ」
`_mmdFindRefreshAfterRender` は appendChunk 経路（render.ts:298）から**チャンクごと**に走る。
find と同じ位置に `if (_mmdJump.isOpen())` ガードを置く（無いと O(N × 文書サイズ)）。

### J13. 見出しプロバイダは最終名で置く
「暫定」と書くだけでは 485.2 が別実装を立てるのを止められない。`HeadingJumpProvider` を
最終名で置き、選択子は `h2, h3` に確定する（`#diagram-wrap` 配下のみ）。

## 実装順序（TDD）

1. **リファクタ前に**、検索側の未担保 2 分岐のテストを足す（空クエリ → `''`、
   正規表現エラー → `''`）。実測で `__tests__` にこの 2 分岐のテストは 0 件であり、
   これが無いと AC #4「挙動不変」を測るものが無い。
2. `formatJumpCount` とインデックス演算を共有モジュールへ切り出し、find.ts を載せ替える
   （既存テストが通ることを確認）。
3. バーの所有者（J3）を導入し、`resolveBarCloseKey` へ一般化する。
4. `jump.ts`（コントローラ + `JumpProvider`）と `HeadingJumpProvider` を TDD で書く。
5. CSS: `mmd-jump-current` を新設。**`tr` に背景色を当ててはいけない**
   （`.diff-add`/`.diff-del` が同じ詳細度 0,1,0 で `tr` に背景を持ち、後勝ちで潰す。style.css:336-342）。
   outline 系にする。`border-collapse: collapse` 下で `tr` の outline が WebKit で描かれるかは
   静的読解では確定できないため、`webview-css-snapshot-harness` の手順で 1 枚撮って確かめる。
   配置は `.mmd-find-bar` が `position: fixed; top/right`(style.css:541-556) なので、
   見た目のクラスだけ共有し配置は別クラスに分ける。
6. Swift 側: `canJump`（J7）、`ViewerBridge` の script 定数と PlainFunction、
   tag 方式の `@objc` アクション（J9）、メニュー項目（キー等価なし）、局在化（J11）。
7. `swift test` / `npm test` / `npm run check:viewer-bundle` / swiftlint ベースライン差分ゼロ。

## 485.2 以降への申し送り（受け取り側の AC にする）

- 485.2: `HeadingJumpProvider` を**差し替えず拡張する**こと。
- 485.3: 左右分割では 1 変更ブロックが左右 2 つの `tr` になる。`JumpTarget.highlight` が
  複数要素を取れる形にしてあるので、それを使うこと。また `_mmdJumpOpen(kind)` は
  fire-and-forget で、文書切替と重なると切替後の文書に対して前の kind でバーが開きうる。
  `diff` kind が差分表示中以外で開かれたときの振る舞いを決めること。
- 差分表示中は `appendChunk` が早期 return する（render.ts:200-202）ため、truncated の間
  目印列が初回描画分のまま止まる。既存の検索と同じ挙動だが、n/N として妥当かを判断すること。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

viewer 側（4 モジュール新設・既存 4 モジュール修正）と Swift 側（ゲート・ブリッジ・メニュー）を入れた。

- `viewer-src/navigation.ts`: 位置の算術 3 関数と件数ラベルの組み立て。検索と共有する純粋部分。
- `viewer-src/bar.ts`: 検索バー / ジャンプバーの排他を単一の所有者（`null | 'find' | 'jump'`）で持つレジストリ。
- `viewer-src/jump.ts`: 目印の列・現在位置・n/N 表示・ハイライト・スクロール・再構築。列挙は持たない。
- `viewer-src/jump-providers.ts`: `HeadingJumpProvider`（`h2, h3` を文書順に列挙）。
- Swift: `ViewerCapabilities.canJump`（ゲートを畳んだ導出）、`ViewerBridge` の 4 スクリプト、
  `DocumentJumpKind`、tag 方式の `documentJump(_:)`、Edit メニュー項目、局在化 5 キー。

## 設計レビューで方針を変えた点（着手前に潰した）

- **`ViewerWindowController` は 869 行 / 恒久例外の上限 900**。検索と同じ流儀で `@objc` を 4 本足すと
  `check-type-group-size.sh --check` が CI で落ちる。tag 方式で 1 本に畳んで 878 行に収めた。
- **⌃⌘G は「変更されたファイルのみ表示」が使用済み**（`MainMenuBuilder+ViewMenu.swift:74-77`）。加えて
  `site/src/lib/shortcuts.ts:38-52` のパーサはゲートを認識しないため、キー等価を付けると
  stable のユーザーへ存在しない機能を告知することになる。`parseCallChunk` が `keyEquivalent:` の無い項目を
  null で捨てる（`site/src/lib/shortcuts.ts:79-81`）ことを実測し、**キー等価を付けない**方針にした。
  site テスト 360 件が通ることを確認済み。
- **ゲートの露出点**を「メニュー構築 1 箇所」から `ViewerCapabilitiesFactory` での注入へ変更。
  `canFind` の実際の消費側は 4 箇所（`WebViewCommandController` の 3 ガード + `ViewerMenuValidator`）で、
  片側だけ塞ぐと素通りする。能力の導出へ畳んで構造で担保した。
- **再構築時のスクロール**を分離。`highlightCurrent` は必ず `scrollIntoView` するので、
  そのまま再構築フックに乗せると appendChunk 経路（スクロール復元が無い）で
  段階読み込み中に読んでいる位置を毎チャンク奪う。`moveTo(index, scroll)` にした。
- **`_mmdModeSwitch.consume()` は破壊的読み出し**なので呼ぶのは 1 箇所に固定し、値を両方へ渡す。
- **開始時の無効化**を `_mmdScroll.beginRender()` と同じ位置に置いた（render は mermaid 描画を await する間
  DOM が既に差し替わっており、着地まで前の文書の n/N が残る）。ただし現在位置は捨てない
  （捨てると再描画のたび先頭へ戻る。テストで捕捉した）。

## 実機で見つけて直したもの

ジャンプバーは検索バーと違い入力欄を持たないためキーボードフォーカスが乗らず、
バー要素の keydown に Enter が届かない（実機で 1/5 のまま動かないことを確認）。
document 側の `resolveJumpNavigationKey` で拾う形へ移した。

## CSS の実測（設計レビューの未確認前提だったもの）

`webview-css-snapshot-harness` の手順でライト / ダーク 2 枚を撮った。

- 見出し（ブロック要素）への `outline` は両テーマで正しく描かれ、差分の背景色も潰さない。
- **`tr` への `outline` は `border-collapse: collapse` 下で上下辺しか描かれない**（左右の縦辺が出ない）。
  485.1 の目印は見出しだけなので影響しないが、TASK-485.3 の AC へ申し送った。

## 検証

- `npm test` 479 件 passed（ジャンプ 21 件を追加）。
- `swift test` 1611 件 passed。
- site `npm test` 360 件 passed（キー等価を付けない判断の裏取り）。
- `swift scripts/webview-smoke.swift` 通過。
- swiftlint はベースライン差分ゼロ（54 件）。`check-type-group-size.sh --check` 通過。
- oxlint / oxfmt / `check:viewer-cycles`（30 モジュール・循環なし）/ `typecheck:viewer` すべてクリーン。
- en/ja の翻訳漏れなし。`markdownlint-cli2` 0 件。`check-doc-symbols.sh` 通過。
- **実装を戻すと落ちることを実測した項目**: 検索の件数表示 2 分岐、バーの排他、
  描画開始時の無効化、無効化が位置を捨てないこと、`consume()` の共有、Enter の配線。
- **実機（Debug ビルド）**: メニューに「見出しへジャンプ…」が出て有効、開くと 1/5 表示で
  最初の h2 に outline（h1 は目印にしない）、Enter で 2/5、Shift+Enter で 1/5、
  Enter 5 回で先頭へ循環、Escape で閉じる、見出しの無いファイルへ切り替えると 0/0 に更新。

## stable 昇格時にやること

キー等価の割り当てと、`site/src/lib/shortcuts.ts` のショートカット表への反映。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
目印の列挙だけを差し替えれば別種のジャンプが作れる共通基盤を作り、最初の利用者として h2 / h3 の見出しジャンプを動かした。FeatureGate 配下に置き stable では露出しない。設計レビューを着手前に回して 5 件の重い指摘（型グループの行数超過・キーバインド衝突・site CI・スクロール奪取・ゲート露出点）を実装前に潰し、実機検証で Enter の配線漏れを 1 件見つけて直した。npm 479 / swift 1611 / site 360 件 passed、swiftlint ベースライン差分ゼロ、実機で全経路の動作を確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
