---
id: TASK-644
title: >-
  SidebarTreePresenter.childTasks の寿命が expansion の寿命と揃っていない（畳んだ配下の券が残る／完了済みの
  Task を保持し続ける）
status: Done
assignee: []
created_date: '2026-09-27 07:24'
updated_date: '2026-09-27 07:58'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/App/SidebarExpansion.swift
  - BefoldApp/befoldTests/SidebarNavigatorReviewExpansionTests.swift
priority: medium
ordinal: 844000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-642（commit d34fc0c5）で `SidebarTreePresenter.childTasks`（pathKey ごとの走行中の子リスト取得）を持たせ、`awaitSettled` がそれを待つようにした。`/code-review high` が寿命の取りこぼしを 2 件指摘し、コードで裏を取った。同型 2 件なので個別修正ではなく、寿命の規則を 1 箇所へ寄せる（`.claude/CLAUDE.md`「同型のバグが 2 回目に出たら構造で塞ぐ」）。

## 現状（検証済み）

1. **畳みの取りこぼし。** `collapseFolder(key)` は `childTasks[key] = nil` だけを外す。一方 `SidebarExpansion.collapse(key)` は `isKey(_:within:)`（`key` 自身と `key + "/"` 接頭辞）で**配下の展開もすべて捨てる**。配下の券は generation が進んで無効化済みだが、その Task は `childTasks` に残る。`awaitSettled` は `childTasks.first` から順に待つので、`a` → `a/deep` を展開（`a/deep` の lister をゲートで止める）→ `a` を畳む → `awaitSettled()` の順で、無効化済みの取得を待ってハングする。これは `childTasks` の doc が「待たないため」と書いている、まさにその場合。
2. **完了済みの保持。** `childTasks` のエントリを外すのは `awaitSettled`（テスト専用）・`collapseFolder`・`invalidateExpansion` だけ。プロダクトでは子リストが着地しても Task ハンドルが残り、フォルダーが展開されている間ずっと保持される（レビュー表示の 400 フォルダーなら 400 個の完了済み `Task<Void, Never>` を窓ごとに保持し、取り直しのたびに上書きで入れ替わる）。読む者はいない。

## 方向

「`childTasks` は走行中の取得だけを持つ」を不変条件にする。着地時に自分のエントリを外す（`expansion.apply` が受け付けたか、または token の世代を比較して、同じ Task なら外す）。畳み・無効化は `SidebarExpansion` が捨てたキーの集合をそのまま `childTasks` にも適用する（`collapse` が捨てたキーを返す、または同じ接頭辞規則で外す）。規則を presenter と expansion で二重に書かない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `a` → `a/deep` を展開し `a/deep` の子リスト取得をゲートで止めたまま `a` を畳んだ後、`awaitSettled()` がハングせず戻るテストがある
- [x] #2 子リストが着地した後の `childTasks` にそのキーのエントリが残らない（走行中の取得だけを持つ）ことを測るテストがある
- [x] #3 `childTasks` の doc コメントが「走行中の取得だけを持つ」という不変条件と、それを守っている経路を述べている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 採用した方針
- 不変条件「childTasks は走行中の有効な取得だけを持つ」。外す経路を 2 つに限定した: (1) 着地: `SidebarExpansion.apply` が Bool を返し、受け付けたら自分のエントリを外す（受理 = その key の最新券なので、エントリは必ず自分）。(2) 無効化: 券を無効にした側が同じ範囲で外す — loadChildren の上書き / reloadExpandedChildren は invalidateChildren で epoch が進むので removeAll してから入れ直す / collapseFolder は `SidebarExpansion.collapse` が返す捨てたキーを外す / invalidateExpansion は removeAll。
- 単純化の検討: Task に自己識別子（token 比較・ID）を持たせて着地時に常に外す案は採らなかった。ゲートで止まった無効化済みの取得は着地しないので、無効化側で外す経路はどのみち要る。それなら受理の Bool だけで足りる。接頭辞規則は collapse の戻り値で受け、presenter へ複製していない。
- 指摘外で見つけた同型: reloadExpandedChildren で行が無いキーを飛ばすと、epoch で無効化された旧取得がエントリに残る。removeAll で塞いだ。
- awaitSettled の『待った後に同じ Task なら外す』は、不変条件が破れても待ち合わせが回り続けないための保険として残した。

## 検証
- 新規テスト SidebarTreePresenterChildTasksTests（2 件）。修正を一時的に戻すと両方落ちる（実測）: collapsingParentDropsDescendantTasks は pendingChildKeys.isEmpty と awaitSettled の 5 秒以内の戻りで失敗、landedTaskRemovesItself は pendingChildKeys が空にならず失敗。
- 最初の版は回帰時に awaitSettled がハングし、.timeLimit でも打ち切れなかった（ゲート待ちはキャンセル非対応）。awaitSettled を別 Task で走らせ waitUntilOnMainActor で戻りを期限付きで見る形にした。
- swift test 全 2005 件 pass / xcodebuild BUILD SUCCEEDED / swiftlint は origin/main 比で新規 0・解消 0（両側 46 件）。
- responsibility-reviewer は起動せず: 増やしたのはテスト用の computed property（pendingChildKeys）と戻り値だけで、型・stored property・注入クロージャは増えていない。
- native-app-design.md / viewer-ui.md への反映は不要（childTasks は内部実装で、文書に出てこない）。

## 追記: full suite での不安定化と対処
- コミット後の Stop フック（swift test --skip Integration --skip FileWatcherTests）で collapsingParentDropsDescendantTasks が 3 回連続で失敗した。ログを入れて実測すると awaitSettled 自体は戻っていたが、待機 Task の開始が full suite の MainActor 直列化で期限（10 秒）より遅れ、期限切れの後に完了していた。壁時計の期限で戻りを測る形そのものが不適切だった。
- 対処: awaitSettled は待ち終えた Task をローカルの集合で飛ばすだけにし、childTasks からは外さないようにした（外すと不変条件の破れを覆い隠す）。テスト 1 は try #require(pendingChildKeys.isEmpty) で先に落としてから awaitSettled を直接待つ。テスト 2 は awaitSettled の後に pendingChildKeys を直接測る。どちらも期限を使わない。
- 再検証: 修正を戻すと 2 件とも 0.001 秒で失敗しハングしない。フック相当のコマンドで 3 回連続 1890 件 pass、swift test 全 2005 件 pass、swiftlint は main 比の差分 0。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SidebarTreePresenter.childTasks に「走行中の有効な取得だけを持つ」不変条件を設けた。受理された着地は自分のエントリを外し、無効化（取り直し・畳み・破棄）した側が同じ範囲で外す。畳みは SidebarExpansion.collapse が返す捨てたキーを使い、接頭辞規則を二重に書かない。回帰すると落ちるテスト 2 件を追加した。
<!-- SECTION:FINAL_SUMMARY:END -->
