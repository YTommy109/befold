---
id: TASK-616
title: 'isRestorable のゲートを迂回する経路が 2 つ残っている（終了時の noteActivated と window(forPath:)）'
status: To Do
assignee: []
created_date: '2026-09-11 13:53'
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
- [ ] #1 スライド窓が main の状態で終了しても、アクティブ記録は直前にキーだった通常窓のパスのまま
- [ ] #2 復元時にキーにする窓の引き当てで、同じパスのスライド窓が通常窓より先に選ばれない
- [ ] #3 `remapController` の rename 分岐も `noteOpened(_:in:)` を通り、`sessionStore.noteOpened` を直接呼ぶ箇所が `ViewerWindowSessionSync` に残らない
- [ ] #4 セッションへ書く経路のうち種別のゲートを通らないものが無いことを、`rg sessionStore\.note` で列挙して Notes に残す
- [ ] #5 1 と 2 は実配線のユニットテストで担保する
<!-- AC:END -->
