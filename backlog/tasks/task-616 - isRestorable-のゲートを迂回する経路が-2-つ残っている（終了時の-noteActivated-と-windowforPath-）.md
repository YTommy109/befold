---
id: TASK-616
title: 'isRestorable のゲートを迂回する経路が 2 つ残っている（終了時の noteActivated と window(forPath:)）'
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-09-11 13:53'
updated_date: '2026-09-11 14:35'
labels: []
dependencies: []
ordinal: 806000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-612 のコードレビュー（finderA / finderSimplify）で確定した指摘。TASK-612 は `ViewerWindowSessionSync` の中でスライド窓をセッションから外したが、`SessionSync` を通らない書き手と読み手が残っている。

1. **`AppDelegate.applicationShouldTerminate` が `noteActivated` を種別を見ずに書く**（コード参照: `AppDelegate.swift` の `applicationShouldTerminate`。`ActiveViewerProvider.fromMainWindow()` の結果をそのまま `stores.sessionStore.noteActivated` へ渡し、その後 `freeze()`）。終了時の最後の書き手なので、スライド窓が main のまま cmd+Q すると `viewerWindowDidBecomeKey` のガードを迂回してアクティブ記録がスライド窓のパスになる。savedURLs / レイアウトはスライド窓を含まないので、再起動時に `window(forPath:)` が nil を返し、本来キーになるべき通常窓がキーにならない。`makeController` の `lastActivePathKey`（サイドバー状態の引き継ぎ）にも古い値が流れる。
2. **`ViewerWindowManager.window(forPath:)` に種別の絞り込みが無い**（コード参照: `ViewerWindowManager+SessionSync.swift`。呼び出し元は `SessionRestorer.restoreLastSession` のキー窓決定の 1 箇所だけ）。起動時の CLI 要求でスライド窓が先に開いていると、復元した通常窓ではなくスライド窓がキーにされる。タイミング依存。
3. **`remapController` の rename 分岐が `sessionStore.noteOpened` を直接呼び、唯一の入口 `noteOpened(_:in:)` を迂回している**（コード参照: `ViewerWindowSessionSync.swift`。TASK-612 で自分が「唯一の入口」と宣言した直後に同じ関数内で迂回している）。両分岐とも rename 固有の `noteRenamed` のあとに `noteOpened(newURL, in: controller)` を呼ぶ形に畳める（`RecentDocumentsStore.noteOpened` の `moveToFront` は冪等なので rename で 1 回多く呼んでも結果は同じ）。

TASK-612 の Notes に書いた「4 つ目のストアが判定を忘れられない形」は SessionSync の内側でしか成立しておらず、AppDelegate と Restorer が外から同じストアを触っている。ゲートをストア側（`SessionStore` が kind を必須で受ける、TASK-610 の `RecentDocumentsStore` と同じ形）へ寄せるかも含めて着手時に決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 スライド窓が main の状態で終了しても、アクティブ記録は直前にキーだった通常窓のパスのまま
- [x] #2 復元時にキーにする窓の引き当てで、同じパスのスライド窓が通常窓より先に選ばれない
- [x] #3 `remapController` の rename 分岐も `noteOpened(_:in:)` を通り、`sessionStore.noteOpened` を直接呼ぶ箇所が `ViewerWindowSessionSync` に残らない
- [x] #4 セッションへ書く経路のうち種別のゲートを通らないものが無いことを、`rg sessionStore\.note` で列挙して Notes に残す
- [x] #5 1 と 2 は実配線のユニットテストで担保する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. `SessionStore.noteActivated(_:kind:)` へ種別を**必須引数**で受けさせ、`guard kind.isRestorable` をストア側に置く(TASK-610 の `RecentDocumentsStore.noteOpened(_:kind:)` と同じ形)。`ViewerWindowSessionSync.viewerWindowDidBecomeKey` の `if controller.kind.isRestorable` は外し、`AppDelegate.applicationShouldTerminate` は `controller.kind` を渡す。書き手が 2 つある唯一のメソッドなので、ここだけ寄せる(noteOpened / noteClosed / noteRenamed の書き手は SessionSync だけ)。
2. `ViewerWindowManager.window(forPath:)` を `first(where: \.kind.isRestorable)` にする。唯一の呼び出し元は `SessionRestorer.restoreLastSession` のキー窓決定で、復元した通常窓を引くのが意図。
3. `remapController` の rename 分岐を `noteOpened(newURL, in: controller)` へ合流させ、`sessionStore.noteOpened` の直接呼び出しを消す(`RecentDocumentsStore.noteOpened` の moveToFront は冪等なので rename で 1 回多く呼んでも結果は同じ)。
4. AC #4 の列挙を Notes に残す。
5. テスト: (a) スライド窓がキーになってもアクティブ記録が直前の通常窓のまま、(b) `noteActivated(_:kind: .slide)` 単体が no-op、(c) 同じパスでスライド窓が先に開いていても `window(forPath:)` は通常窓を返す。

### /review-design の結果（実装前）

- 項目 3（兄弟箇所の全列挙）: 窓の種別を見ずにストアを触る箇所を洗った。`windowFrame.recordUserAdjustedFrame(_:for:)` は kind 必須、`recentDocumentsStore.noteOpened(_:kind:)` / `noteRenamed(from:to:kind:)` も kind 必須、`recentRepositories.recordTabGroup(of:)` は `ViewerTabGrouping.viewerPath(of:)` が `isRestorable` で落とす。`bookmarkStore.noteRenamed` は種別に関係なく効くべき（ブックマークはファイル単位）。残る穴は `sessionStore.noteActivated` だけ。
- 項目 3（`remapController` の順序）: `sessionStore.noteRenamed` は activeKey を旧→新へ書き換えるので、`noteClosedIfNoWindowRemains(oldURL)`（旧パスと一致する activeKey を消す）より**前**に置く必要がある。合流後も rename 固有の 3 つ（sessionStore.noteRenamed / recentDocumentsStore.noteRenamed / bookmarkStore.noteRenamed）を先に済ませ、そのあと noteClosed → `noteOpened(_:in:)` の順にする。recentDocuments と bookmark の noteRenamed が noteClosed より前へ移るが、`noteClosedIfNoWindowRemains` が触るのは sessionStore だけなので影響しない（コード参照: `ViewerWindowSessionSync.noteClosedIfNoWindowRemains`）。
- 項目 3（二重呼び出しの確認）: `RecentDocumentsStore.noteRenamed` は内部で `noteOpened(newURL, kind:)` を呼んでいる（コード参照: `RecentDocumentsStore.noteRenamed(from:to:kind:)`）。合流で 2 回目の `noteOpened` が走るが `recentPaths` の moveToFront は冪等なので結果は同じ。タスク説明の前提は裏が取れた。
- 項目 2（`window(forPath:)` の意味）: フィルタを入れると「開いている窓を引く」という一般名と意味がずれる。呼び出し元は本番では `SessionRestorer.restoreLastSession` の 1 箇所だけ（実測: `rg 'window\(forPath'`、他 8 箇所はテスト）なので、名前は据え置きにして doc へ「復元の対象になる種別の窓だけを返す」と明記する。テスト側の用途はすべて通常窓なので挙動は変わらない。
- 項目 7（測るものと守るもの）: AC #1 の `AppDelegate.applicationShouldTerminate` そのものはヘッドレスで実行できない。担保は**必須引数という構造**（渡し忘れがコンパイルエラーになる）とし、テストは (a) スライド窓がキーになってもアクティブ記録が変わらない実配線と (b) `noteActivated(_:kind: .slide)` 単体の no-op で測る。この「実配線では測れていない範囲」を Notes に明記する。
- 項目 9（決めたことを守らせるもの）: `kind` を必須引数にするのが破れない構造。`noteOpened` / `noteClosed` / `noteRenamed` は書き手が `ViewerWindowSessionSync` だけなので同じ形にはせず（YAGNI）、代わりに AC #4 の列挙を Notes に残す。
- 項目 10（行数）: `SessionStore` 135 行 → 約 139 行、`ViewerWindowSessionSync` 115 行 → 約 113 行（合流で減る）、`ViewerWindowManager` グループ 326 行 → 約 330 行（実測: `scripts/check-type-group-size.sh`）。責務の増分なし。
- 項目 1 / 4 / 5 / 6 / 8: 該当しない（判定は `kind` という事実、新しい表示状態なし、`guard` の追加は順序非依存、`viewerWindowDidBecomeKey` への追加コストなし、非同期なし）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### AC #4: セッションへ書く経路の列挙（実測: `rg 'sessionStore\.note' --type swift BefoldApp/ | grep -v Tests`）

| 書き手 | メソッド | 種別のゲート |
| --- | --- | --- |
| `ViewerWindowSessionSync.noteClosedIfNoWindowRemains` | `noteClosed` | 残っている窓を `isRestorable` で数える |
| `ViewerWindowSessionSync.noteOpened(_:in:)` | `noteOpened` | `if controller.kind.isRestorable` |
| `ViewerWindowSessionSync.remapController`（rename） | `noteRenamed` | `if controller.kind.isRestorable` |
| `ViewerWindowSessionSync.viewerWindowDidBecomeKey` | `noteActivated` | **ストア側**（`kind` 必須引数） |
| `AppDelegate.applicationShouldTerminate` | `noteActivated` | **ストア側**（`kind` 必須引数） |
| `SessionRestorer.restoreLastSession` の `onMissing` | `noteClosed` | 窓が無い経路（実在しないファイルの記録削除）なので種別は無関係 |

ゲートを通らない書き手は残っていない。`remapController` が直接呼んでいた `sessionStore.noteOpened` は消え、`noteOpened(_:in:)` が唯一の入口に戻った。

**兄弟ストアも同時に確認した**: `windowFrame.recordUserAdjustedFrame(_:for:)` / `recentDocumentsStore.noteOpened(_:kind:)` / `noteRenamed(from:to:kind:)` はいずれも kind 必須。`recentRepositories.recordTabGroup(of:)` は `ViewerTabGrouping.viewerPath(of:)` が `isRestorable` で落とす。`bookmarkStore.noteRenamed` は種別に関係なく効くのが正しい（ブックマークはファイル単位）。

### 実装

1. `SessionStore.noteActivated(_:kind:)` に `guard kind.isRestorable` を置き、`kind` を必須引数にした（TASK-610 の `RecentDocumentsStore.noteOpened(_:kind:)` と同じ形）。`ViewerWindowSessionSync` 側の `if` は外した。
2. `ViewerWindowManager.window(forPath:)` を `first { $0.kind.isRestorable }` にした。名前は据え置き（本番の呼び出し元は `SessionRestorer.restoreLastSession` の 1 箇所のみで、他 8 箇所はテスト）。
3. `remapController` の rename 分岐を `noteOpened(_:in:)` へ合流。rename 固有の 3 つ（sessionStore / recentDocuments / bookmark の `noteRenamed`）を先に済ませてから `noteClosedIfNoWindowRemains` → `noteOpened` の順にした（`sessionStore.noteRenamed` がアクティブ記録を旧→新へ書き換えるので、旧パス一致で記録を消す `noteClosed` より前である必要がある）。`RecentDocumentsStore.noteRenamed` が内部で `noteOpened` を呼ぶため 2 回通るが、moveToFront は冪等なので結果は同じ。

### 検証（実測）

- 新規テスト 3 件が passed: 「スライド窓がキーになっても、直前の通常窓のアクティブ記録は変わらない」「同じパスでスライド窓が先に開いていても、window(forPath:) は通常窓を返す」「復元の対象でない種別の noteActivated は既存のアクティブ記録を上書きしない」。
- **修正を外すと 3 件とも落ちることを確認した**（ストア側の guard と `window(forPath:)` のフィルタを一時的に無効化 → `savedActivePath()` が `/mock/second.mmd`・`/tmp/slide.mmd` になり、`window(forPath:)` がスライド窓を返した）。
- `swift test` 全体 2007 tests passed。`/swiftlint-baseline` の origin/main 差分ゼロ。

### 実配線では測れていない範囲（AC #1 の注記）

`AppDelegate.applicationShouldTerminate` そのものはヘッドレスで実行できないため、終了経路の実配線テストは無い。担保は **`kind` が必須引数であること**（渡し忘れがコンパイルエラーになる。実際この変更の途中で当該行がコンパイルエラーになり、そこで直した）と、同じストアメソッドを測る上記のユニットテスト。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`isRestorable` のゲートを迂回していた 3 経路を塞いだ。(1) `SessionStore.noteActivated` が `kind` を必須引数で受けてストア側でゲートするようにし、終了時の `AppDelegate` からの書き込みも通るようにした。(2) `ViewerWindowManager.window(forPath:)` が復元対象の窓だけを返すようにした。(3) `remapController` の rename 分岐を `noteOpened(_:in:)` へ合流させ、`sessionStore.noteOpened` の直接呼び出しを消した。新規ユニットテスト 3 件で担保し、修正を外すと 3 件とも落ちることを確認。セッションへ書く全経路の列挙は Notes に記録。
<!-- SECTION:FINAL_SUMMARY:END -->
