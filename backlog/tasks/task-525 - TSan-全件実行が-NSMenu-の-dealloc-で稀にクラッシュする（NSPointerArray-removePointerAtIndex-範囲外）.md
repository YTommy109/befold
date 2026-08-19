---
id: TASK-525
title: >-
  TSan 全件実行が NSMenu の dealloc で稀にクラッシュする（NSPointerArray removePointerAtIndex
  範囲外）
status: Done
assignee:
  - '@claude'
created_date: '2026-08-19 02:17'
updated_date: '2026-08-19 06:37'
labels:
  - bug
dependencies: []
priority: medium
ordinal: 767000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`swift test --sanitize=thread` の全件実行 4 回のうち 1 回、テストはすべて pass しながらプロセスが signal 6 で落ちた。

## 事実（実測 2026-08-19、TASK-516 の検証中）

- 手元（macOS 26 / arm64）で TSan 全件実行を 4 回。3 回は `1649 tests in 264 suites passed`、1 回だけ以下で abort。

```text
*** Terminating app due to uncaught exception 'NSInvalidArgumentException',
reason: '*** -[NSConcretePointerArray removePointerAtIndex:]: attempt to remove pointer at index 5 beyond bounds 5'
  3 AppKit -[NSPointerArray removePointersInRange:]
  4 AppKit -[NSPointerArray removePointersPassingTest:]
  5 AppKit -[NSMenu _setMenuName:]
  6 AppKit -[NSMenu dealloc]
  7 AppKit -[NSMenuItem dealloc]
```

- 落ちた時点で失敗テストは 0 件。«unknown» issue も出ていない（TASK-516 で扱った協調スレッド枯渇とは別物）。
- スタックは AppKit 内部のみで、befold のフレームを含まない。メニューを組み立てるテスト（MainMenuBuilder 系）の `NSMenu` / `NSMenuItem` が並行に dealloc されている疑い。

## 未確認

- 再現率 1/4 は TSan 実行のみでの実測。通常実行でも起きるかは未確認。
- TASK-516 の変更（`Task.detached` → `withBlockingWork`）以前から起きていたかは未確認。CI の thread-sanitizer ジョブの過去ログを漁れば分かる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 TSan 全件実行を反復し、再現率と、TASK-516 以前から起きていたかを実測する
- [x] #2 原因がメニュー系テストの NSMenu 寿命管理にあるなら、dealloc が並行しない形へ直す
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CI の thread-sanitizer ジョブ過去ログを全件確認し、TASK-516 以前から signal 6 の abort があるかを実測する（完了）
2. NSMenu を保持したままテスト境界を越えるオブジェクトを洗い出す（完了: MainMenuFixture.cachedMenu のみ）
3. deinit にスレッド計測を仕込み、フィクスチャの解放が非メインで起きているかを実測する（完了: 23 テストで 36/36 が非メイン）
4. 単純化で塞ぐ: MainMenuFixture のメモ化(cachedMenu)を削除し、メニュー木の寿命を @MainActor なテスト本体のローカル変数に閉じる
5. 破れたら落ちる担保: weak 参照でフィクスチャがメニュー木を保持しないことを検証するテストを追加し、cachedMenu を戻すと落ちることを確認する（確認済み）
6. TSan 全件実行を baseline 5 回 / 修正後 5 回まわし、abort の有無を比較する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## AC#1 の前半（TASK-516 以前から起きていたか）: CI ログの実測

直近 30 件の ci.yml 実行（push/schedule）のうち失敗 8 件について thread-sanitizer ジョブのログを全件取得して調査した（`gh api repos/:owner/:repo/actions/jobs/<id>/logs`）。

- **signal 6 による abort は TASK-516（c57d34aa, 2026-08-19 02:40 UTC）以前から起きている。** run 32103739053 / job 95609053684（2026-08-18 05:44 UTC）で `swiftpm-testing-helper ... exited with unexpected signal code 6`。直前まで失敗テストは 0 件で、全 pass の途中で落ちている点も手元の症状と同じ。
- ただしその回の abort 理由は `Fatal error: Attempted to read an unowned reference but object 0x159b2a180 was already destroyed` で、NSPointerArray ではない。**CI ログ 8 件のいずれにも `NSConcretePointerArray` の文字列は出ていない**（grep 実測 0 件）。
- 残る 7 件の失敗はテスト失敗（diffContent の未確定判定、fileGone 検出、watcherCallback 等）で abort ではない。

結論: 「TSan 全件実行の最後で寿命管理起因の abort が稀に出る」現象は TASK-516 より前から存在する。NSPointerArray 版の署名は CI では未観測（手元 macOS 26 のみ）。

## AC#1 の後半（再現率）: 手元での実測 2026-08-19

修正前のツリー（e6dace6e 相当）で `swift test --sanitize=thread` の全件実行を 5 回。**5 回とも pass、abort は 0 回**（各ログを `NSConcretePointerArray` / `unexpected signal` で grep して確認）。

したがって起票時の 1/4 と合わせても手元の観測は 1/10 程度で、**「修正後に出なくなった」ことを再現の有無で示すことはできない**（数回の pass は偶然でも成立する）。原因の裏付けは再現率ではなく下記の直接計測で取った。

## 原因の直接計測

`MainMenuFixture` に一時的な `deinit { if !Thread.isMainThread { NSLog(...) } }` を入れて
`swift test --filter "MainMenuBuilderTests|MenuShortcutCatalogTests"` を実行したところ、
**23 テストの実行でログが 36 行、すなわち観測されたフィクスチャ解放がすべて非メインスレッド**だった。

`@MainActor final class` でも `deinit` は非隔離であり、Swift Testing がスイート値を破棄する
スレッドはメインとは限らない。フィクスチャが `cachedMenu` でフルメニュー木を握っているため、
その解放が `NSMenu.dealloc` → `_setMenuName:` を非メインで走らせ、AppKit がメニュー名の登録に
使うプロセスグローバルな `NSPointerArray` を並行に書き換える。クラッシュのスタック
（`NSMenuItem dealloc → NSMenu dealloc → _setMenuName: → removePointersPassingTest:`）と一致する。

なお `NSMenu` をテスト境界を越えて保持しているのは `MainMenuFixture.cachedMenu` だけで
（`befoldTests/*.swift` のスイート直下 stored property を全数確認）、他のメニュー系テストは
すべて `@MainActor` なテスト関数のローカル変数として作って同じ関数内で解放している。

## 修正と検証

- `befoldTests/MainMenuFixture.swift`: `cachedMenu` によるメモ化を削除（状態も分岐も増やさない単純化）。メニュー木の寿命が `@MainActor` なテスト本体のローカル変数に閉じ、解放がメインスレッド上になる。コストは実測で 2 スイート 24 テスト計 0.08 秒なので、メモ化の価値は無い。
- `befoldTests/MainMenuBuilderTests.swift`: 担保として `fixtureDoesNotRetainTheMenuTree` を追加（weak 参照でフィクスチャがメニュー木を保持しないことを検証）。**`cachedMenu` を戻すと落ちることを実測で確認済み**（`swift test --filter fixtureDoesNotRetainTheMenuTree` が 1 issue で失敗）。

検証:

- `swift test --sanitize=thread` 全件を修正後に 3 回: いずれも `1663 tests in 266 suites passed`、`NSConcretePointerArray` / `unexpected signal` の出現 0 件。ただし baseline 5 回でも abort が出なかったため、**この 3 回の pass は「直った」ことの証拠にはならない**（原因の裏付けは非メイン deinit の直接計測）。
- swiftformat（fix モード）実行後、swiftlint を main と比較して**新規違反ゼロ**（正規化後 42 件で一致）。

ドキュメント: 変更はテストフィクスチャの寿命管理のみで、アプリの仕様・構成は変わらないため `docs/dev/native-app-design.md` の更新は不要と判断した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TSan 全件実行が稀に NSMenu の dealloc で abort する原因を特定し、テストフィクスチャの単純化で塞いだ。

原因: `MainMenuFixture` が `cachedMenu` でフルメニュー木を保持していたため、その解放が Swift Testing によるスイート値の破棄と同じスレッドで起きていた。`@MainActor final class` でも `deinit` は非隔離であり、一時的な計測（deinit で Thread.isMainThread をログ）では 23 テストの実行で 36 回すべて非メインスレッドだった。ここから NSMenu.dealloc → _setMenuName: が並行に走り、AppKit がメニュー名の登録に使うプロセスグローバルな NSPointerArray が壊れる。クラッシュのスタックと一致する。

修正: メモ化（cachedMenu）を削除し、メニュー木の寿命を @MainActor なテスト本体のローカル変数に閉じた。フル構築のコストは 2 スイート 24 テストで計 0.08 秒。担保として weak 参照でフィクスチャがメニュー木を保持しないことを検証する fixtureDoesNotRetainTheMenuTree を追加し、cachedMenu を戻すと落ちることを確認した。

検証: TSan 全件を修正後 3 回（1663 tests / 266 suites 全 pass、abort 0）。swiftformat 適用後の swiftlint は main と比べて新規違反ゼロ。CI ログ調査で、signal 6 の abort は TASK-516 より前（2026-08-18）から起きていたことも確認。なお baseline 5 回では abort が再現しなかったため、修正の裏付けは再現の消失ではなく非メイン deinit の直接計測に置いている。
<!-- SECTION:FINAL_SUMMARY:END -->
