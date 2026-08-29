---
id: TASK-563
title: サイドバーを開いてもフォーカスが移らないことがある（初回の展開）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-28 02:15'
updated_date: '2026-08-28 02:26'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 813000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
⌘S でサイドバーを開いてもフォーカスがサイドバーへ移らず、矢印キーが効かない。ユーザー報告（2026-08-28）:「Claude がスライドをプレビューした後、befold を起動して ⌘S を押すと毎回発生する」。

## 再現（2026-08-28 実測 / befold 1.15.0）

セッション復元で起動し、**そのプロセスで初めてサイドバーを開いたとき**に起きる。System Events の `AXFocusedUIElement` を読んで観測した。

| 手順 | フォーカス |
|---|---|
| 復元起動の直後（サイドバーは畳んだ状態） | AXWebArea |
| ⌘S 1 回目（開く） | **AXWebArea のまま = 不具合** |
| ⌘S 2 回目（閉じる） | AXWebArea |
| ⌘S 3 回目（開く） | AXOutline（正常） |
| ⌘S 4 回目（閉じる） | AXWebArea |

**flaky。** 起動から ⌘S までの待ち時間を変えて 6 回試行したところ、待ち 1.5 秒で 3 回中 1 回失敗、待ち 6 秒では 3 回中 0 回失敗。**起動直後に押すほど再現しやすい**。ユーザー環境では毎回とのことなので、マシンの速度や一覧の件数で頻度が変わると考えられる。

サイドバー自体は 1 回目で開いている（開かないのではなく、フォーカスだけが移らない）。

## 原因

`SidebarTableFocuser.focus(retriesRemaining:)` は `tableView` 参照が未解決なら次のランループで再試行するが、**5 回で打ち切って黙って諦める**。以後の再試行は無い。

`tableView` の代入は `FileListView` の**行の背景**（`SidebarTableViewLocator`）で行われるため、**行が 1 つも描かれるまで参照は現れない**。畳んだ状態から初めて開く周期では、一覧の読み込みと List の初回レイアウトがフォーカス要求に間に合わないことがあり、5 ランループを超えると要求が消える。2 回目以降は行が既に描かれていて参照があるため成功する。

## 直し方（同じファイルに手本がある）

`SidebarTableFocuser` は**スクロール要求では既に正しい形**を実装している（`pendingScroll` に要求を保持し、一覧の差し替え後に `retryPendingScroll()` で再試行、成功したら要求を消す）。フォーカスも同じ形にする。

- 回数制限の再試行をやめ、`focusPending` フラグで要求を保持する
- `tableView` の `didSet` で保留中の要求を成立させる
- **サイドバーを畳んだら保留を取り消す**（遅れて行が描かれたときに、閉じた後のサイドバーへフォーカスを奪わせない = 開始時の無効化）

## Acceptance Criteria の補足

回帰テストは「参照が後から現れる」順序を再現する必要がある（先に `focus()`、後から `tableView` を代入）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tableView 参照が後から現れる順序でも、サイドバーへフォーカスが移る
- [x] #2 サイドバーを畳んだ後に参照が現れても、フォーカスを奪わない
- [x] #3 上の 2 つを固定するテストがあり、修正を戻すと落ちる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 直した内容

`SidebarTableFocuser` の**フォーカス要求を、回数で待つのをやめて事実（参照が現れたか）で成立させる**形に変えた。同じ型が `pendingScroll` で既に採っている形に揃えている。

- `focus()` は `focusPending` を立てて即時に試み、成立しなければ保持する（旧: 5 ランループだけ再試行して黙って諦める）
- `tableView` の `didSet` で保留中の要求を成立させる（参照は行の背景 `SidebarTableViewLocator` から来るので、行が描かれた瞬間がここ）
- `cancelPendingFocus()` を足し、**サイドバーを畳んだ時点で保留を捨てる**。捨てないと、遅れて行が描かれたときに閉じたはずのサイドバーがフォーカスを奪う（開始時の無効化）
- 配線は `ViewerSplitViewController` の `onSidebarDidHide`（新設）→ `ViewerWindowAssembler`。**この引数に既定値を持たせていない**——渡し忘れると「開いた要求が閉じた後に成立する」形が静かに戻るため、コンパイルエラーにする（TASK-319 の教訓）

## 検証

- 回帰テスト 2 本を追加し、**実装だけ旧版へ戻すと「tableView が後から現れてもフォーカスを移す」が落ちる**ことを確認（`window.requestedFirstResponder → nil`）。もう 1 本（畳んだ後は奪わない）は旧版でも通るので、こちらは cancel の配線が担保
- `swift test`: **1723 tests / 275 suites すべて通過**
- swiftformat 実行後、swiftlint を main と比較: **54 件 → 54 件、真の新規ゼロ・解消ゼロ**
- 新規ファイルは無いので `xcodegen generate` は不要

## 未検証

**実アプリでの再現消滅は未確認。** 元の再現が flaky（待ち 1.5 秒で 3 回中 1 回、待ち 6 秒で 0 回）なので、「出なくなった」を実測で示すには試行を重ねる必要がある。ユニットテストは参照が後から来る順序そのものを固定しているため機構は押さえているが、実機確認は次にビルドを配ったときに行う。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの初回展開でフォーカスが移らない原因は、SidebarTableFocuser が tableView 参照を 5 ランループだけ待って諦めていたこと。参照は行の背景から設定されるため、畳んだ状態から初めて開く周期では間に合わないことがある。要求を保持して参照が現れた時点で成立させる形（同じ型の pendingScroll と同じ形）へ変え、畳んだ時点で保留を捨てる配線を必須引数として足した。回帰テストは実装を戻すと落ちることを確認、swift test 1723 件通過、swiftlint の新規違反ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
