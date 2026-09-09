---
id: TASK-547
title: Edit メニューの構築を分割する（MainMenuBuilder が閾値に近い）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-23 16:34'
updated_date: '2026-09-08 15:35'
labels:
  - refactor
dependencies: []
ordinal: 797000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

`scripts/check-type-group-size.sh` の閾値は 400 行（`:29`）。`BefoldApp/befold/App/MainMenuBuilder` グループは **377 行**で、残り 23 行しかない（TASK-485.4 の /review-design 項目 10 で実測）。

TASK-485.4 自体は `DocumentJumpKind.allCases` のループに乗るため増分 0 行だったが、次に Edit / View メニューへ項目を 1 つ足すと超える距離にある。

## 方針

`MainMenuBuilder+ViewMenu.swift` の前例に倣い、Edit メニューの構築を `MainMenuBuilder+EditMenu.swift` へ切り出す。ただし CLAUDE.md が戒めるとおり **extension へ切っても合算行数は減らない**ので、行数だけを目的にしない。責務として「Edit メニューの構成」が独立した関心かを見て判断し、独立していなければ別の受け皿（型の新設）を検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `MainMenuBuilder` を責務で分割しない判断が、TASK-585 の再調査になった経緯つきで `docs/dev/rules/product-code.md` に残っている
- [x] #2 例外行を消すときに理由（判断）の行き先を決める、という運用が同じ節に明文化されている
- [x] #3 `MainMenuBuilder.swift` の型 doc から上記の置き場へ辿れる
- [x] #4 `makeWindowMenuItem` の stale な doc コメントが実態へ直っている
- [x] #5 `addDisplayModeItems` が唯一の呼び出し元と同じ `MainMenuBuilder+ViewMenu.swift` にある
- [x] #6 check-type-group-size.sh が exit 0 で、site のショートカット検証と swift test が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
/review-design の結果、Description の方針（`+EditMenu.swift` への切り出し）は AC を満たせないと判明したため、ユーザー確認のうえ「分割せず、判断を残して閉じる」へ方針変更した（2026-09-09）。

1. `docs/dev/rules/product-code.md` の責務分離節へ 2 つ書く。(a) 例外行を消すときは理由（判断）の行き先を決める、という一般則。(b) `MainMenuBuilder` を分割しない判断と、その 3 つの根拠。
2. `MainMenuBuilder.swift` の型 doc に (b) へのポインタを 2 行で置く。**本文をコードへ書くとグループが 415 行になって閾値を超えるため、規約文書側に置く。**
3. 派生の小修正 2 件: `makeWindowMenuItem` の stale な doc を実態へ直す（4 行のまま）、`addDisplayModeItems` を `+ViewMenu.swift` へ移す。
4. 派生の残り 2 件（product-code.md の 900/931 ずれ、閾値に近いグループ 10 件）は TASK-603 / TASK-604 として別起票する。
5. check-type-group-size.sh / swift test / site の shortcuts.test.ts / swiftlint で検証する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## /review-design の結果（2026-09-09、実装着手前）

**結論: Description の方針（`MainMenuBuilder+EditMenu.swift` への切り出し）では AC#1 も AC#2 も満たせない。** 方針の再決定が要る。

### 前提の実測

| 前提 | 裏付け | 結果 |
|---|---|---|
| グループは 397 行で残り 3 行 | `scripts/check-type-group-size.sh` | そのとおり（起票時 377 → 現在 397） |
| extension へ切っても合算は減らない | `check-type-group-size.sh` の `collect()`（`Foo+Bar.swift` を `Foo` へ畳む） | **0 行減。AC#1 は達成不能** |
| 切り出しが緩めるのは別の閾値 | enum body 228 行 / `.swiftlint.yml` の `type_body_length` warning 250 | **緩むのは type_body_length（残り 22 行）であって グループ 400 ではない**。起票時の目的設定がずれている |
| 責務として独立した単位があるか | `MainMenuBuilder.swift:21-22` は `@MainActor enum`。stored property 0 / protocol 準拠 0 / 注入クロージャ 0 | **規約が関心の同居を測る指標が全てゼロ。「どのメニューか」という並列分類しかない**（responsibility-reviewer が独立に同結論） |

### 決定的: この問いは TASK-585 で既に答えが出ていた

`git show 3ff54263:scripts/type-group-exceptions.txt` に、当時登録された恒久例外が残っている。

> BefoldApp/befold/App/MainMenuBuilder	420	メインメニューの静的な項目定義そのもので、項目 1 つが 4〜6 行を占める。項目を足す以外に太る要因が無く、**責務で切っても「メニュー項目の定義」以上には分かれない**（+ViewMenu / +FileMenu 等の分割は合算されるため返済にならない）。TASK-585 でスライドモードの項目を足して 403 行になった

TASK-585 の Notes「対応しなかった指摘」にも同じ結論がある。その 2 日後 `88145fc6` で 397 行へ戻り、**例外行が理由ごと削除された**（`check-type-group-size.sh` が「不要な例外」を exit 2 で警告するため）。

つまり TASK-547 は、既に下されていた判断が消えた跡地に立っている。**例外エントリは行数のラチェットであると同時に判断の記録でもあり、後者は 400 行を下回っても失効しない。** これは例外ファイルの運用（「返済して閾値以下へ戻せたらこの行を消す」）の穴。

### 消費経路の制約（チェック項目 1・3）

- `site/vitest.config.ts:52-62` が `name.startsWith('MainMenuBuilder')` のファイル名 glob で全件連結。`.github/workflows/site.yml:32` の paths も同じ glob。
- **prefix から外れた型を新設すると、`site/test/shortcuts.test.ts:218` の `toEqual`（両辺の集合比較）で Edit の 9 件が不足して落ちる。** 黙っては通らない。ただし落ちるのは glob 内のファイルも同時に変更したときだけで、**その後に新型だけを触る変更では site CI が起動しない**（paths フィルタ）。ここが残る穴。
- 実行時に `NSMenu` を読む側（`MenuShortcutCatalog` / `MainMenuFixture` / 各テスト）はファイル配置に非依存。
- キー等価を定義する場所は `MainMenuBuilder*` と `BookmarkShortcut.keyEquivalent` だけ（他は全て `keyEquivalent: """"`。実測）。「情報源の一本化」は成立している。

### Edit メニューは今後確実に増える

- TASK-485.16（ゲート外し）: `DocumentJumpKind.allCases` の 3 項目 + セパレータが stable で常時構築へ
- TASK-485.25: その 3 項目にキー等価を割り当て
- `FeatureGate.isDocumentJumpEnabled` は現在 stable で false（`project.yml` の MARKETING_VERSION 1.17.1 はプレリリース記法なし）

### チェックリストの非該当（1 行ずつ）

- 項目 4（新しい状態の表示）: UI 状態を増やさないため非該当
- 項目 5（ライフサイクル・順序）: `build()` の呼び出し順は不変。`NSApp.servicesMenu / windowsMenu / helpMenu` の副作用は App / Window / Help メニューにあり、Edit には無いため切り出しの影響なし
- 項目 6（高頻度経路）: メニュー構築は起動時 1 回のため非該当
- 項目 8（非同期の世代管理）: 非同期処理が無いため非該当

### 派生して見つかった不整合（この差分の外）

1. `MainMenuBuilder.swift:188-191` の doc が **stale**。View メニューの説明が `makeWindowMenuItem` に付いている。`git blame` で全行 `6d371d300`（当時は `makeViewMenuItem` の直前で正しかった）、`3c2e3a4e` で本体だけ `+ViewMenu.swift` へ移りコメントが取り残された。**既存の `+ViewMenu` 分割が責務ではなく行数で引かれた直接の証拠**でもある。
2. `addDisplayModeItems`（`MainMenuBuilder.swift:232-248`）は View メニュー専用で唯一の呼び出し元が `+ViewMenu.swift:16` なのに本体側にある。凝集の観点では `+ViewMenu.swift` 側が正しい置き場（ただし合算は不変）。
3. `docs/dev/rules/product-code.md:138` が恒久例外を「上限 900 行」と書くが、実際は 931（`type-group-exceptions.txt`）。TASK-585 で 920、TASK-593 で 931 と動いたが doc が追随していない。
4. 閾値 380 行以上のグループが恒久例外を除いて 10 件ある（`SidebarExpansionTests` 399 / `AppDelegate` 398 / `SidebarNavigator` 398 / `MainMenuBuilder` 397 / …）。MainMenuBuilder は最も逼迫しているグループではない。

## 方針変更（2026-09-09、ユーザー確認済み）

上の /review-design の結果を受けて「`+EditMenu.swift` へ切り出す」から「分割せず、判断を残して閉じる」へ変更した。旧 AC（#1 グループに余裕ができている / #2 責務分離になっている理由 / #3 xcodegen + xcodebuild）は達成不能または無意味になったため書き換えた。

## 実装

1. `docs/dev/rules/product-code.md` の責務分離節へ 2 項目を追加。
   - **一般則**: 例外行を消すときは、そこに書いた「理由」の行き先を決める。3 列目には判断が書かれることがあり、それは閾値以下へ戻っても失効しない。移す先はコードの doc コメントを第一候補、入り切らなければ規約文書か ADR。TASK-585 → TASK-547 の再調査を実例として併記した。
   - **`MainMenuBuilder` を分割しない判断**と 3 つの根拠（指標が全部ゼロ / 合算は減らない・緩むのは type_body_length / site の glob から外れる）。400 行を超えたら分割ではなく恒久例外へ登録する、まで書いた。
2. `MainMenuBuilder.swift` の型 doc に 2 行のポインタ。
3. `makeWindowMenuItem` の stale な doc を実態へ修正（4 行のまま。Window メニューは NSWindow / NSApplication の標準セレクタだけで、この型で唯一アプリ固有型へ委譲しないメニューである旨）。
4. `addDisplayModeItems` を `MainMenuBuilder.swift` から `MainMenuBuilder+ViewMenu.swift` へ移動（唯一の呼び出し元が `+ViewMenu.swift:16`。実測で他に参照なし）。

## 判断の置き場をコードにできなかった理由（実測）

最初は判断の本文を `MainMenuBuilder.swift` の型 doc（18 行）に書いた。結果グループが **415 行**になり閾値 400 を超えた。**判断を書き残す余裕がグループに無い**ため、本文を規約文書へ移して 2 行のポインタだけを残す形にした。この事実自体が TASK-604（閾値に張り付いたグループの棚卸し）の根拠でもある。

## 別起票

- TASK-603: `product-code.md` の恒久例外の記述が実態とずれている（900 → 931）
- TASK-604: 型グループの閾値に張り付いているグループを棚卸しする（380 行以上が 10 件）

## 検証

- `scripts/check-type-group-size.sh --check`: exit 0（グループは 397 → **399**。ポインタ 2 行の増分。移動は合算に対して増減なし）
- `swift test`: 1942 tests / 320 suites 全て pass
- `site` の `npx vitest run test/shortcuts.test.ts`: 9 tests pass（`addDisplayModeItems` を別ファイルへ移しても glob が両方を拾うため、ショートカット検証は不変）
- `swift build`: 成功
- swiftlint: 出力 51 行に `MainMenuBuilder` の指摘は 0 件（main と同数）
- swiftformat: 変更なし
- `scripts/check-doc-citations.sh` / `scripts/check-doc-symbols.sh`: いずれも exit 0
- `markdownlint-cli2`: 0 issues
- `xcodegen generate` は不要（ファイルの新規追加・削除なし）

## 現在仕様への反映

`docs/dev/native-app-design.md` は更新しない。メニューの構成・振る舞いは一切変わっておらず、変更は doc コメントと規約文書と関数 1 つの置き場のみ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
/review-design の結果、当初の方針（`MainMenuBuilder+EditMenu.swift` への切り出し）では AC を満たせないことが判明した。型グループはファイル名で合算されるため extension 分割では 1 行も減らず（緩むのは swiftlint の type_body_length の方）、`MainMenuBuilder` は stored property・protocol 準拠・注入クロージャがいずれも 0 個で責務分離の軸自体が存在しない。さらに同じ結論が TASK-585 で既に出ており、恒久例外の 3 列目に理由つきで記録されたあと、397 行へ戻った時点で「不要な例外」として行ごと削除されていた（`git show 3ff54263:scripts/type-group-exceptions.txt` で確認）。

ユーザー確認のうえ方針を「分割せず、判断を残して閉じる」へ変更し、`docs/dev/rules/product-code.md` へ (a) 例外行を消すときは理由の行き先を決める、という一般則と (b) `MainMenuBuilder` を分割しない判断と 3 つの根拠を書いた。判断の本文をコードの doc コメントに置くとグループが 415 行になって閾値を超えるため、コード側には 2 行のポインタだけを残した。あわせて派生の小修正 2 件（`makeWindowMenuItem` の stale な doc、`addDisplayModeItems` の置き場）を実施し、残る 2 件は TASK-603 / TASK-604 として別起票した。

検証: check-type-group-size.sh exit 0（399 行）、swift test 1942 件 pass、site の shortcuts.test.ts 9 件 pass、swiftlint は main と同数で MainMenuBuilder の指摘 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
