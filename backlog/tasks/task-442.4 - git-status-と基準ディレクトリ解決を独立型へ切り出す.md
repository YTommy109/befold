---
id: TASK-442.4
title: git status と基準ディレクトリ解決を独立型へ切り出す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-11 07:35'
updated_date: '2026-08-11 11:53'
labels: []
dependencies:
  - TASK-442.3
parent_task_id: TASK-442
ordinal: 676000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarNavigator から git 関心を 2 つの独立型へ出す。1 つにまとめない理由は、性質の違う 2 つの非同期関心だから。基準ディレクトリ解決の書き込み先は fileListModel.baseDirectory (相対パスコピー・Quick Open のヘッダー表示) で、git バッジ経路 (fileListModel.applyGitStatus → .git/index 監視 → host.gitStatusDidApply) とは別。resolveGitRoot の唯一の呼び出し元は refreshBaseDirectory であり、git status 側は resolveGitRoot を必要としない。

(A) SidebarBaseDirectoryResolver: resolveGitRoot / baseDirectoryGeneration / pendingBaseDirectoryTask / refreshBaseDirectory()
(B) SidebarGitStatusCoordinator: loadGitStatuses / makeGitIndexWatcher / gitIndexWatch / gitStatusGeneration / pendingGitStatusTask / refreshGitStatuses(policy:) / applyGitStatus / awaitingCancellable / performListing の git 側待ち合わせ

(B) の設計上の要点。

- 反映通知はクロージャ注入にせず、既存の SidebarNavigatorHost を weak で直接持つ。gitStatusDidApply() は「バッジと差分の更新契機を 1 つにする」判断をコンパイル時に守らせるための必須メソッド (SidebarNavigator.swift:16-22 / TASK-330) であり、クロージャを 1 段挟むとその意図が薄まる。host は super.init 後にしか渡せないため attach(to:) で結線する。
- 世代を型の外へ漏らさない。現在 gitStatusGeneration は 3 箇所 (単発取得 :152 / 一覧との結合取得 :253 / 一括無効化 :313) で進んでおり、採番点を型の内側 1 つに閉じることがこの分割の実質的な利得。採番済み sequence を持つ「券」を返す API にして、performListing は券を受け取るだけにする。
- 分離できたかの判定基準: cancelPendingListing の git 関連 4 行 (世代加算 / invalidatePendingGitStatus / pendingGitStatusTask.cancel / gitIndexWatch.stop) が coordinator の 1 メソッド呼び出しへ畳めること。畳めないなら分離できていない。
- TASK-293/294/297 の不変条件を壊さないこと。絞り込み ON のときは一覧と git 結果を同一 Task・同一メインアクター実行で反映し、OFF のときは分ける。反映の可否判定 (recency + ディレクトリ対付け) は従来どおり FileListModel.applyGitStatus(_:for:sequence:) に置いたままにする (ADR 0003)。
- テストの観測点 pendingGitStatusTask / pendingBaseDirectoryTask は約 30 箇所ある。互換用の委譲プロパティは残さない (本体に git 側 stored への参照が残ると上の判定基準が使えなくなる)。テスト側を新型へ向け直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 基準ディレクトリ解決と git status 取得がそれぞれ独立型へ切り出され、resolveGitRoot は基準ディレクトリ側だけが持つ
- [x] #2 git status 側の反映通知が SidebarNavigatorHost の weak 参照であり、そのためのクロージャ注入が無い
- [x] #3 gitStatusGeneration に相当する採番が新型の内側だけで行われ、SidebarNavigator は sequence を読み書きしない
- [x] #4 cancelPendingListing の git 関連処理が新型の 1 メソッド呼び出しへ畳まれている
- [x] #5 絞り込み ON で一覧と git 状態が同一メインアクター実行で反映されることを担保する既存テスト (SidebarNavigatorListingCoherenceTests) が通る
- [x] #6 新型は private 保持で、外部は SidebarNavigator の薄い委譲と読み取り専用の窓だけを使う（stored への直接参照が無い）
- [x] #7 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarBaseDirectoryResolver.swift を新設（@MainActor final class）。resolveGitRoot / generation / pendingTask / refresh() / cancelPending() を持つ。fileListModel を init で受け、baseDirectory だけを書く。
2. SidebarGitStatusCoordinator.swift を新設。loadGitStatuses / makeGitIndexWatcher / gitIndexWatch / generation / pendingTask / weak host を持つ。API は attach(to:) / refresh(policy:) / beginRequest(for:) -> StatusRequest / awaitResult(_:) / apply(_:for:) / publishDetached(_:) / adopt(pendingTask:) / cancelPending()。sequence は StatusRequest の fileprivate に閉じ、SidebarNavigator から読み書きできなくする（AC#3）。
3. performListing を券ベースへ書き換える。絞り込み ON は一覧タスク内で awaitResult → apply → onApplied（同一メインアクター実行を維持 / TASK-293,294,297）、OFF は publishDetached。
4. cancelPendingListing の git 4 行を gitStatus.cancelPending() の 1 呼び出しへ、基準ディレクトリ側を baseDirectory.cancelPending() へ畳む（AC#4）。
5. 注入クロージャを 3 個以下にする（AC#6）。resolveGitRoot / loadGitStatuses / makeGitIndexWatcher の 3 本を 1 つの依存値へまとめ、init 引数を directoryLister / childrenLister / その 1 値の 3 個にする。※この形が妥当かは設計レビューで確認する。
6. テストの観測点（pendingGitStatusTask 約 26 箇所 / pendingBaseDirectoryTask）を新型のプロパティへ向け直す。委譲プロパティは残さない。ReferenceResolutionCoordinator.swift の参照も確認する。
7. xcodegen generate → swift build → swift test → swiftformat → swiftlint 差分 → 型グループ計測 → ベースライン更新。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 設計レビュー結果 (実装前 / 2026-08-11)

responsibility-reviewer を回した。指摘 7 件のうち High 3 件が実装方針に影響したため、着手前に 3 点を確定させた。

### 1. AC#6 (注入クロージャ 3 個以下) を本タスクから外し TASK-442.6 へ切り出した

レビューの指摘: resolveGitRoot / loadGitStatuses / makeGitIndexWatcher を 1 つの struct へ束ねる案は数合わせ。本数は変わらず保持先が移るだけで、しかも本タスクが「書き込み先も用途も別」として 2 型へ分けた関心が依存値の側で 1 つに戻る。makeGitIndexWatcher の既定は FileWatcher でありファイル監視なので、GitAccess 等の名前も嘘になる。

実測: プロダクトが実際に渡すのは resolveGitRoot / loadGitStatuses の 2 本だけ (ViewerWindowAssembler.swift:48,51)。残り 3 本はテスト専用の既定値。また規約が問題視するのは親→子のコールバック注入であり、この 5 本はいずれも下位への問い合わせ (依存供給) でコールバックではない。

ユーザー判断で「別タスクへ切り出す」を採用。TASK-442.6 (protocol SidebarGitReading への置き換え) を起票した。AC#6 は本タスクの AC から削除し、代わりに「新型は private 保持で外部は薄い委譲と読み取り専用の窓だけを使う」を AC#6 とした。

### 2. adopt(pendingTask:) を廃止する

レビューの指摘: 絞り込み ON のとき coordinator の pendingTask が一覧取得タスクそのものになり、新型の doc に「これは git 取得タスクです」と書けなくなる。存在理由はテスト観測点だけで、Description が禁じた委譲プロパティと逆方向の同じ漏れ。

採用する。ON では git 反映が一覧タスク内で起きるのが TASK-293 の不変条件そのものなので、テストは pendingListingTask を待つ形へ向け直す。これで coordinator の API は 1 本減る。

### 3. awaitResult と apply は融合しない (API 2 本の露出を維持する)

レビューの指摘: awaitAndApply へ融合すれば API は減るが、現行は await の後に guard generation == listingGeneration, let host = self.host があり、一覧世代が古ければ git 結果を反映しない (SidebarNavigator.swift:305-313 / TASK-294 が理由付けした箇所)。融合するとこのガードを間に挟めない。

融合しない側を採る。FileListModel の recency 判定 (ADR 0003) が最終的に受けるため破綻はしない可能性が高いが、TASK-294 が明示的に理由を書いた挙動を API を 1 本減らすために変えるのは取引として悪い。「ガードを維持するために API 2 本を露出し続ける」ことを coordinator の doc に記録する。

### 4. coordinator / resolver は private + 薄い委譲 (Description の文言を訂正)

442.3 の tree と同形にする。Description の「互換用の委譲プロパティは残さない」は「stored への参照を残さない」の意味であり、読み取り専用の窓 (expandedFolderKeys が先例) は可とする。refreshGitStatuses のプロダクト呼び出し元は ReferenceResolutionCoordinator.swift と ViewerWindowController+WindowDelegate.swift にあるため、委譲メソッドは必要。

### 5. 世代ガードのイディオムを共通型へ括らない (理由を記録する)

レビューの指摘: 分割後、「世代 + pendingTask + cancelPending」が navigator / (A) / (B) の 3 箇所に並ぶ。TaskGeneration のような値型へ括るか、括らない理由を記録するかを決めよ。

括らない。3 つは同じ形に見えるが守っているものが違う。navigator の listingGeneration は「一覧の反映 + host 生存」を、(A) は「単一プロパティ書き込み」を、(B) の sequence は**型の外へ渡って FileListModel.applyGitStatus の recency 判定に使われる** (ADR 0003) 。(B) だけは局所的なガードではなく他の型との契約なので、同じ値型に押し込めると (B) の sequence が「内部の実装詳細」に見える。3 コピー目だが同じ知識ではない。

### 行数見積もり

レビューの実測見積もり: 本体 391 行から約 105 行減り、委譲で 10〜15 行戻るため型グループは 551 → 約 455〜460。442.5 で +History 70 行を出しても約 385〜390 で、親 AC#1 (400 行以下) には入るが余裕は 10〜15 行。442.5 着手前に「History を出しても navigator 側に委譲が何行残るか」を先に見積もること。

## 検証結果 (実装後)

- swift test: 1297 tests / 182 suites すべて成功。**テストの変更は不要だった**。pendingGitStatusTask / pendingBaseDirectoryTask を読み取り専用の computed property として残したため、約 30 箇所の観測点はそのまま動く
- swiftlint: ブランチ HEAD (d6d87a4) との比較で真の新規 0 件 / 解消 0 件
- 型グループ: SidebarNavigator 551 → **493 行**。新設は SidebarGitStatusCoordinator 179 行 / SidebarBaseDirectoryResolver 65 行
- xcodegen generate 実行済み、ベースライン更新済み

## adopt(pendingTask:) を廃止しても既存テストが成立する理由 (実測)

絞り込み ON の経路を検証するテストは、いずれも **pendingListingTask を先に await してから** pendingGitStatusTask を await する形で書かれていた (SidebarNavigatorChangedFilesOnlyTests:90-91,98-99 / SidebarChangedFilesOnlyIntegrationTests:52-53,93-94,127-128,155-156)。ON の反映は一覧タスクの中で起きるため、前者の await で既に担保されている。

SidebarNavigatorListingCoherenceTests の 2 件 (:211 / :237) は refreshGitStatuses を呼んだ直後に pendingGitStatusTask を捕まえており、これは変更前後とも**単発取得のタスク**を指す (performListing が先に載せた値を refreshGitStatuses が上書きするため)。したがって意味は変わらない。

つまり adopt は最初から不要で、一覧タスクを git 側の pending に載せ替える必要はなかった。

## 親 AC#1 (400 行以下) の見通し

493 行から 400 以下にするには 93 行以上の削減が必要。442.5 の原資は +History 70 行 + +SelectionMemory 23 行 = 93 行ちょうどで、**委譲メソッドが 1 行でも残ると届かない**。442.5 の着手前に、applyHistoryEntry (442 の Notes が「本体の File List 関心そのもの」と指摘しており単純移動できない) を含めて残行を先に見積もること。届かない場合の追加の切り口 (performListing の doc の圧縮、refreshFileList の選択決定部の切り出し等) を着手前に決める。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SidebarNavigator から git 関心を 2 型へ切り出した。SidebarBaseDirectoryResolver (65 行) が resolveGitRoot と fileListModel.baseDirectory の書き込みを、SidebarGitStatusCoordinator (179 行) が git status の取得・反映・.git/index 監視を持つ。発行順序の採番は coordinator 内の StatusRequest (fileprivate) に閉じ、SidebarNavigator は sequence を読み書きしない。cancelPendingListing の git 4 行と基準ディレクトリ 2 行は、それぞれ cancelPending() の 1 呼び出しへ畳んだ。設計レビューの指摘を受けて adopt(pendingTask:) は作らず、絞り込み ON の反映は一覧タスク内に残した (既存テストは元から pendingListingTask を先に await していたため変更不要)。awaitResult と apply を融合しなかったのは、その間の一覧世代ガード (TASK-294) を保つため。型グループ 551 → 493 行。swift test 1297 件成功、swiftlint 新規 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
