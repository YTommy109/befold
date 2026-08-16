---
id: TASK-503
title: ショートカット一覧にメニュー外のキー操作を載せる
status: Done
assignee: []
created_date: '2026-08-16 11:41'
updated_date: '2026-08-16 13:08'
labels:
  - chore
dependencies: []
priority: medium
ordinal: 111500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Help > キーボードショートカットは MenuShortcutCatalog がメインメニューから生成しており（BefoldApp/befold/App/MenuShortcutCatalog.swift:38-51）、メニュー項目に割り当てたキーは漏れなく載る。一方、メニューを経由しないキー操作が一切載らない。

載っていないもの（TASK-502 の調査で判明）:
- ビューア内スクロール: Space / ⇧Space（ページ）、j / k / ↑ / ↓（行）、⇧+それら（半ページ）、Esc（検索バーを閉じる）— BefoldApp/viewer-src/keyboard.js:36-48, :56
- サイドバーのキー操作: j/k/↑/↓ 選択、l/→/Return で進む、h/← で戻る・畳む、⌘↑ と delete で親へ、⌘Return 新規タブ、⌘⇧Return 新規ウィンドウ — BefoldApp/befold/Viewer/SidebarKeyAction.swift:60-85
- Quick Open パネル内の ↑/↓/Tab/Esc — BefoldApp/befold/App/QuickOpenView.swift:41-56
- マウス/トラックパッド操作: ⌃ホイールでズーム、水平スワイプで戻る/進む、⌘クリック / ⌘⇧クリック / ⌃クリック — docs/dev/native-app-design.md:247, 258-262

論点は「メニュー由来の一覧に、別の情報源のものをどう混ぜるか」。メニュー定義を唯一の情報源にした TASK-240 の判断を壊さない形（例: 由来ごとにセクションを分け、非メニュー分はそれぞれの実装側に定義を持たせて引く）で設計する。載せる文言をビューにハードコードするのは、同じ乖離を作り直すことになるので採らない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ビューア内スクロール・サイドバー・Quick Open のキー操作がショートカット一覧に載っている
- [x] #2 マウス/トラックパッド操作を載せるかどうかを判断し、結論を Implementation Notes に残している
- [x] #3 非メニュー由来の項目も、表示用の文字列をビューにハードコードせず実装側の定義から導いている
- [x] #4 実装側の割り当てを変えたときに一覧との乖離が検出できるテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計レビュー（/review-design）の結果を反映した計画。

## 方針

Help の一覧を「由来ごとのセクション」に広げ、非メニュー由来の項目は各実装の隣に置いた
カタログ型から引く。表示文字列はビューに置かず、キー表記は 1 か所で組み立てる。

## 手順

1. `ShortcutKey`（修飾キー + キー）を新設し、`displayName` を導出する。
   `MenuShortcutCatalog.keyDisplay(of:)` をこの型経由に置き換え、⌃⌥⇧⌘ の順序規則を 1 か所にする。
2. 表示用の `ShortcutSection` / `ShortcutEntry` と、メニュー由来 + 非メニュー由来を連結する
   組み立て点を作る。`KeyboardShortcutsView` はセクションを並べるだけにする。
   `MenuShortcutCatalog` 自体と `MenuShortcutCatalogTests.everyAssignedShortcutAppears()` は
   メニュー由来だけを見る形のまま変えない（TASK-240 の担保を薄めない）。
3. サイドバー: `SidebarShortcutCatalog` を `SidebarKeyAction.swift` の隣に置く。
   ディスパッチの switch は書き換えない。
4. Quick Open: `QuickOpenKeyAction` を新設し、`QuickOpenView` の `.onKeyPress` 4 か所と
   **`.onSubmit`(Return)** をこの型経由にする。
5. ビューア内スクロール: `Escape` の判定を `keyboard.js` の純粋関数へ切り出し、
   `resolveScrollKey` と同じ経路で検証できるようにする。
   Swift 側に `ViewerScrollShortcutCatalog` を置き、jest 側で Swift ソースをパースして突合する。
6. 文言は Localizable.xcstrings に追加し、カタログがキーを持つ。ビューにリテラルを置かない。

## テスト（設計レビューで確定した担保）

- サイドバー / Quick Open は **双方向**で縛る。
  - 健全性: カタログの各キーが宣言どおりのアクションへ解決される
  - 完全性: 候補キーを総当たりし、`.ignored` 以外を返すキーは必ずカタログに載っている
    （片方向だとディスパッチャにキーを足したとき Help が黙って古いままになる）
- JS 突合テストは **パース結果が 0 件なら失敗**させる（空集合の検証は必ず通るため）。
  Swift 側テストでも同じカタログの件数をアサートし、両側が同じ列を数えている状態にする。
- Escape は純粋関数へ切り出してから載せる。載せて未検証のまま残さない。

## 判断（Notes に残す）

- マウス/トラックパッド操作は載せない方針で進める（ウィンドウ名がキーボードショートカットであり、
  キー表記を持たないため）。最終結論は実装時に確定して Notes に記録する。
- 配布サイトの /features の SHORTCUTS 表には手を触れない。非メニューのキーを足すと
  site 側のテスト（実装集合 = MainMenuBuilder 由来）が落ちるため、載せるかは別タスクとする。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## マウス/トラックパッド操作を載せるかの判断（AC #2）

**載せない。** 理由は 3 つ。

1. パネルの名前が「キーボードショートカット」(`keyboardShortcuts.windowTitle`)で、⌃ホイールズーム・
   水平スワイプ・⌘クリックはキー表記(`ShortcutKey.displayName`)を持たない。同じ表の
   「キー」列に入れると、列の意味が「キー表記」から「操作の説明」に変わる。
2. 修飾キー + クリックは既に `docs/dev/native-app-design.md:220-224` に記述があり、
   ⌘クリック / ⌘⇧クリックの意味づけは `OpenDisposition` に集約されている
   （サイドバーの ⌘Return / ⌘⇧Return として一覧には載る。同じ意味づけの
   キーボード側は載り、マウス側だけが載らない形になる）。
3. 載せる場合は突合の相手が `reference-clicks.js` の postMessage 経路と
   `SwipeHistoryNavigation` になり、AC #3・#4 を満たす形にすると本タスクの
   2 倍近い作業量になる。別タスクとして切り出すのが妥当。

## 実装内容

- `ShortcutKey`(新規): 修飾キーの並び順(⌃⌥⇧⌘)を知る唯一の型。NSMenuItem / SwiftUI の
  KeyEquivalent / ビューアの KeyboardEvent.key の 3 経路から作れる。
  `MenuShortcutCatalog.keyDisplay(of:)` はこの型を経由する実装に置き換えた。
- `ShortcutSection` / `ShortcutEntry`(新規): 表示の器。`MenuShortcutCatalog.Group` /
  `.Entry` は typealias にして既存の呼び出しとテストをそのまま通した。
- `HelpShortcutSections`(新規): メニュー由来 + 非メニュー由来 3 セクションの連結点。
  `KeyboardShortcutsView` はこれを並べるだけ。
- `ViewerShortcutCatalog` / `SidebarShortcutCatalog` / `QuickOpenShortcutCatalog`(新規)。
  表示するキー表記は、いずれも**ディスパッチに渡す値そのもの**から導く
  （`KeyEquivalent` + `EventModifiers`、または KeyboardEvent.key + shift）。
- `QuickOpenKeyAction`(新規): `QuickOpenView` の `.onKeyPress` 4 か所と `.onSubmit`(Return) を
  この型経由にした。設計レビューで指摘した「Return だけ別の場所にある」を解消。
- `viewer-src/keyboard.js`: Escape の判定を純粋関数 `resolveFindCloseKey` へ切り出した
  （ハンドラ内の分岐のままでは突合テストの対象にできず、載せても未検証になるため）。
- ローカライズ 21 キーを追加。挿入のみで既存行の並べ替え・整形は 0 行
  （xcstrings は 12 件だけ Xcode 形式の `" : "` が混ざっており、JSON 往復すると
  無関係な 22 行が書き換わる。テキスト挿入で回避した）。

## 検証（実測）

- `swift test` 1583 tests / 251 suites すべて通過（新規 25 件を含む）
- `npm test`(jest) 445 tests / 8 suites すべて通過（新規 6 件を含む）
- `npm run lint` / `format:check` / `typecheck:viewer` すべてクリーン
- swiftformat: fix モードを回して機械に決めさせた後 `--lint` で違反 0
- swiftlint: main とのベースライン差分は **1 件の移動のみ**。
  `identifier_name`(Identifiable の `id`)が `MenuShortcutCatalog.swift` から
  `ShortcutSection.swift` へ移った（型の移動に伴う）。総数は 54 → 54 で増減なし、
  新しいルールの違反は無い。
- 実アプリ(`xcodebuild build -scheme befold`)の `en.lproj` / `ja.lproj` に
  21 キーすべてが訳付きで入っていることを `plutil -p` で確認した。

## テストが空振りしないことの確認（変異テスト）

修正を戻して落ちることを 5 通り実測した。

1. `SidebarKeyAction` に新しいキー(`"g"`)を足す → 完全性テストが失敗
2. `keyboard.js` の `j` の割り当てを外す → jest の突合が失敗
3. Swift カタログのリテラル形式を崩す → パース件数 7→6 で失敗（0 件を成功にしない）
4. `keyboard.js` の `j` を外して再測（テスト書き換え後）→ 失敗を再現
5. ローカライズキー 1 件を削除 → `LocalizationTests` が失敗

## 実装中に見つかった事実

- **`SidebarKeyAction.action` は ⌘ 以外の修飾キーを見ない。** ⌥J も ⇧K も素の J / K と
  同じ動作になる（switch の条件が ⌘ だけ）。完全性テストはこれを踏まえ、
  「効き方が一覧のどれとも違う組み合わせ」だけを必須にしている。単純に
  「反応する組み合わせはすべて載せる」にすると、同じ動作の行が修飾キーの数だけ増える。
- **swiftformat が長い宣言を折り返すため、1 行前提の正規表現は壊れる。** 実測で 7 件のうち
  1 件が折り返され、パースが 6 件になった。空白・改行を跨げる正規表現に直した。
  この失敗自体は「0 件（件数不一致）で落とす」ガードが検出したもの。
- **swift test では String Catalog がコンパイルされない**（`LocalizationTests.swift:8-10` に既述）。
  そのため `String(localized:)` の結果でローカライズを検証しようとすると必ず失敗する。
  カタログ JSON 側にキーがあることで担保する形へ変えた（既存の LocalizationTests に合流）。

## 現在仕様への反映

`docs/dev/native-app-design.md` に 2 か所追記した（App/ のコンポーネント表と表示仕様）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Help > キーボードショートカット に、メニューを経由しない操作（ビューア内スクロール・サイドバー・Quick Open）を由来ごとのセクションとして追加した。

表示文字列はビューに持たず、キー表記は `ShortcutKey` に集約し、各項目のキーは**ディスパッチへ渡す値そのもの**（KeyEquivalent + EventModifiers、または KeyboardEvent.key + shift）から導く。メニュー由来の抽出と `MenuShortcutCatalogTests` は変更していないので、TASK-240 の「メニュー定義が唯一の情報源」は維持されている。

乖離検出は双方向。健全性（載せたキーは実際に動く）に加えて完全性（動くキーは必ず載っている）を対にしたので、ディスパッチにキーを足したときも落ちる。JS 側は実装が JavaScript にあるため、Swift のカタログを jest がパースして `resolveScrollKey` / `resolveFindCloseKey` に通す（`site/` が MainMenuBuilder を読む手口と同じ）。Escape はハンドラ内の分岐だったので純粋関数へ切り出してから載せた。

検証: swift test 1583 件 / jest 445 件すべて通過。swiftlint はベースライン差分 1 件（型の移動に伴う identifier_name の移動、総数 54→54 で増減なし）。テストが空振りしないことを 5 通りの変異で確認済み（新しいキーの追加・JS 割り当ての変更・カタログ形式の破壊・ローカライズキーの削除いずれも失敗する）。実アプリの en/ja バンドルに 21 キーが訳付きで入ることを plutil で確認。

マウス/トラックパッド操作は載せない判断（理由は Implementation Notes）。
<!-- SECTION:FINAL_SUMMARY:END -->
