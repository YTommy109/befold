---
id: TASK-566
title: FileWatcher がメインスレッドで open() を呼び、遅いパスでアプリが固まる
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-29 12:43'
updated_date: '2026-08-29 23:57'
labels:
  - bug
dependencies: []
ordinal: 823000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状

セッション復元で iCloud Drive 上のファイルを開き直したとき、アプリ全体が数秒固まる。
その間はメニューも開かず、`open` で送ったファイルも処理されない（イベントが溜まる）。
ユーザーには「PDF の描画が遅い」として現れた（実際には種別に関係ない）。

## 原因（実測 / 2026-08-29）

`sample`（3 秒）を取ったところ、**2611/2611 サンプルすべてがメインスレッドの
`open()` システムコールで止まっていた**。呼び出し経路:

```
applicationDidFinishLaunching → SessionRestorer.restoreLastSession
  → ViewerWindowManager.openViewer → makeController → ViewerWindowController.init
  → ViewerWindowAssembler.openInitialDocument → ViewerStore.openFile
  → FileWatcher.init → startMonitors → startDirectoryMonitor → makeMonitor → open()
```

`FileWatcher.init` は監視対象と**その親ディレクトリ**を `open()` で開く。この呼び出しが
`_dispatch_lane_barrier_sync_invoke_and_complete` 経由でメインスレッドから同期に走るため、
対象が iCloud Drive のようにアクセスに時間のかかる場所（さらに TCC の許可ダイアログを
伴う場合）だと、その間アプリ全体が止まる。

`.claude/CLAUDE.md` の「高頻度経路のコスト」で名指ししている型（メインアクター上に
残った同期 syscall。TASK-322 と同じ形）にあたる。

## やること

`FileWatcher` の監視開始（ディスクリプタの取得）をメインスレッドから外す。
開始が非同期になる間に届く変更を取りこぼさないこと。

## 論点（実装着手前に `/review-design` で詰める）

- 監視開始を非同期にすると、「開始したつもりで開始していない」区間ができる。
  その間のファイル変更をどう扱うか（開始直後に 1 回読み直す等）。
- `FileWatcher` は `@unchecked Sendable` で内部キューを持つ。開始をそのキューへ
  移すだけで済むか、`ViewerStore` 側の期待（init 直後に監視済み）を変える必要があるか。
- 既存のテストは一時ファイルの実 FS を使う。非同期化で待ち合わせが要るなら、
  タイミング依存の flaky を作らない形にすること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FileWatcher の監視開始がメインスレッドを塞がない
- [x] #2 監視開始が非同期になっても、開始直後の変更を取りこぼさない
- [ ] #3 遅いパス（ネットワーク/iCloud 等）を開いてもアプリが固まらないことを確認した手順が Implementation Notes にある
- [x] #4 既存の FileWatcher テストが通り、タイミング依存の flaky を新設していない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計レビュー（`/review-design` 1 回目）を反映済みの計画。

## 前提（裏付けつき）

- **「init から戻れば監視が有効」という不変条件は、今も成立していない。** `befoldTests/TestSupport.swift` の `confirmWatcherArmed` の doc コメントが「`DispatchSource.resume()` は同期的に戻るが、kevent のカーネル登録は dispatch のマネージャスレッドで非同期に完了する。そのため `FileWatcher.init` 直後は `.delete` / `.rename` のような一度きりのイベントを取りこぼしうる」と明記している（ドキュメント参照）。`queue.sync` が保証しているのは `open()` と `resume()` の呼び出しまでで、arm ではない。よって非同期化は**取りこぼしの窓を広げる**変更であって、新種の取りこぼしを作る変更ではない。
- **`FileWatcher` の生成箇所は 2 つ**（コード参照）。`ViewerStore+FileWatching.openFile`（表示中の文書）と `GitIndexWatch.update(indexURL:)`（`.git/index`）。`SidebarNavigator` の `makeGitIndexWatcher` は後者の既定ファクトリで、独立した 3 つ目ではない。
- **catch-up 通知は 2 経路とも冪等**（コード参照）。文書側は `ViewerContentState.applyDisplayState` が `isUnchanged`（contentHash + fileType 一致）で何も書き換えず false を返す。git 側は `SidebarGitStatusCoordinator` が `.onlyIfIndexChanged` で問い合わせ、`GitStatusStore.cachedResultIfIndexUnchanged` が stat 1 回（メインアクター外）でキャッシュを返して git を起こさない。

## 手順

1. `FileWatcher.init` の `queue.sync { startMonitors() }` を `queue.async` へ変える。監視キューは直列なので、後続の `stop()`（`queue.sync`）とイベントハンドラは必ず開始ブロックの後に走る。`stop()` が先に呼ばれても「開始 → 停止」の順で確定し、開始ブロックが張った監視は取り残されない。

2. 開始ブロックの末尾で `scheduleNotify()` を 1 回呼び、arm までの取りこぼしを埋める（AC #2）。上の前提のとおり 2 経路とも冪等なので、新しい状態・フラグ・引数は足さない。`stop()` が先着した場合は `debouncer.cancel()` がこの通知も消す（デバウンサー経由で予約されるため）。

3. **`init` の doc コメントを直す。** 現在の「戻り時点で監視が有効になる」は上の前提に照らして誤りで、非同期化で更に離れる。「戻り時点では監視の開始が予約されただけ」であること、arm の完了は観測できないこと、その穴を手順 2 の catch-up が埋めることを書く。

4. **`queue.sync` へ戻したら落ちるものを用意する**（レビュー項目 9）。`FileWatcher.swift` のソースを走査し、`init` 本体に `queue.sync` が現れないことを固定するテストを足す。既存の前例は `ViewerBridgeContractTests`（viewer 側の撤去済みコードの復活を走査で防いでいる）。**このテストが測るのはソースの字面であって、メインスレッドが塞がらないことそのものではない**（レビュー項目 7）。振る舞いの確認は手順 5 の手動手順が担う。

5. 遅いパスでの検証手順を Implementation Notes に残す（AC #3）。ネットワークボリューム等でセッション復元し、メニューが即座に開くこと・`sample` の結果にメインスレッドの `open()` が出ないことを確認する。

6. `swift test` の全体実行と、`/swiftlint-baseline` による main との差分ゼロを確認する。

## レビューで「該当しない」と判断した項目

- 項目 1（判定の真実の源）: 新しい述語を足さない。判定は増えない。
- 項目 4（新しい状態の表示）: ユーザーに見える新しい状態は生まれない。catch-up は内容が同じなら何も描かない。
- 項目 5（ライフサイクル・順序）: 順序の変化は直列キューで確定する。手順 1 に記載。
- 項目 6（高頻度経路のコスト）: このタスク自体が高頻度経路から同期 syscall を外す変更。catch-up の増分は文書 1 回の再読込（hash 一致なら描画なし）と stat 1 回。
- 項目 8（非同期の世代管理）: 表示状態を差し替える非同期取得ではない。差し替えは既存の `loadContent` 側が持つ。
- 項目 10（型グループの行数）: `BefoldApp/befold/FileWatching/FileWatcher` は実測 244 行。追加は doc コメント修正と 1 行の呼び出しで、+15 行程度。責務・プロトコル準拠・stored property のいずれも増えない。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-30）

`FileWatcher.init` の `queue.sync { startMonitors() }` を `queue.async { startMonitorsAndCatchUp() }` へ変えた。`open()` は監視キュー（qos: .utility）上で走るようになり、呼び出し元のスレッドは待たない。

### catch-up を無条件通知にしなかった理由（設計を実装中に変えた点）

計画では「開始直後に `scheduleNotify()` を無条件で 1 回呼ぶ」としていた。**これは誤りで、実装して初めて分かった。** `ViewerStore.loadContent` は呼ばれるたびに `loadGeneration` を進め、古い世代の結果を `performLoad` の着地で破棄する。したがって開いた直後の無条件通知は、**走行中の初回読み込みの結果を捨てて読み直させる**。

実測: この形にすると `ViewerStoreIntegrationTests.deletingWatchedFileFiresOnFileGone` が `(store.contentState.content → "") == "graph TD; A-->B"` で失敗した（初回読み込みの結果が捨てられ、`await store.loadTask?.value` の直後に content が空のままだった）。ファイルを開くたびに毎回起きる形なので、テストだけの問題ではない。

代わりに、監視開始の**前後**で `FileFingerprint`（inode・サイズ・更新時刻。stat 1 回）を撮り、**変わっていたときだけ**通知する形にした。埋まるのは「このブロックが動き始めてから監視が張られるまで」＝非同期化で広げた `open()` の所要時間そのもので、遅いパスではここが支配的になる。

**埋まらない区間は残る。** (a) init から監視キューがブロックを走らせるまでのディスパッチ待ち、(b) `resume()` から kevent のカーネル登録が完了するまで。(b) は非同期化以前から存在していた穴で（`confirmWatcherArmed` の doc コメントが明記している）、このタスクで塞いだものではない。どちらも `open()` の待ち時間とは桁が違う。

### 退行を止めるもの

`befoldTests/FileWatcherStartsOffCallerThreadTests.swift` を追加した。`FileWatcher.swift` の `init` 本体を走査し、`queue.sync` が現れないことと catch-up の呼び出しが残っていることを固定する（前例: `SidebarRowAssemblySingleSourceTests`）。**このテストが測るのはソースの字面であって、メインスレッドが塞がらないことそのものではない。** 実際に `queue.sync` へ戻して実行し、`Expectation failed: (blocking → ["        queue.sync { self.startMonitorsAndCatchUp() }"]).isEmpty → false` で落ちることを確認した。

### 検証（AC #3 の手順）

自動テストでは「固まらないこと」を測れないため、遅いパスでは次の手順で確認する。

1. iCloud Drive（できればダウンロード前の dataless ファイル）かネットワークボリューム上に対象ファイルを置く。
2. そのファイルを開いた状態でアプリを終了し、セッション復元で開き直す。
3. 復元直後にメニューバーをクリックする。**即座に開けば合格**（修正前はここが数秒開かなかった）。
4. 併せて `sample befold 3` を復元直後に取り、メインスレッドのスタックに `open()` が居ないことを確認する。修正前は 3 秒のサンプル 2611/2611 がメインスレッドの `open()` だった。

**この手順は未実行。** 実測できる遅いパスを手元に用意していないため、実行結果ではなく手順として残す。

### 自動検証の結果

- `swift test`: 1798 tests / 291 suites すべて通過（0 失敗）。
- swiftlint: main とのベースライン差分ゼロ（54 件 → 54 件、ルール × ファイルの新規・解消ともに無し）。
- 途中 1 回、`ViewerRendererZoomIntegrationTests` と `ViewerRendererOneShotIntegrationTests` が WebKit の例外で失敗したが、同じコードで再実行すると通った（環境起因の flaky で、この変更とは無関係）。

## 受け入れ基準の裏付け（2026-08-30）

- **AC #1（メインスレッドを塞がない）✅**: `queue.async` は定義上呼び出し元を待たない。退行は `FileWatcherStartsOffCallerThreadTests` が止める（`queue.sync` へ戻して落ちることを実測済み）。
- **AC #2（開始直後の変更を取りこぼさない）✅（範囲つき）**: 監視開始の前後の `FileFingerprint` 比較で埋める。`FileFingerprintTests` 5 件で、内容変更・削除・同内容での差し替え（inode 変化）を変化として拾い、無変更では等しいことを固定した。**埋まらない区間は上記のとおり 2 つ残る**（ディスパッチ待ちと kevent 登録待ち）。後者は非同期化以前から存在した穴で、このタスクが作ったものではない。
- **AC #3（遅いパスで固まらないことの確認手順）⬜ 未チェック**: 手順は上に書いたが**実行していない**。iCloud Drive の dataless ファイルやネットワークボリュームを手元に用意できず、`sample` で「固まらないこと」を実測できていない。手順の記載だけで基準を満たしたことにはしない。
- **AC #4（既存テストが通り、flaky を新設していない）✅**: `swift test` 1803 tests / 292 suites すべて通過。新規テストは 3 件ともファイルシステムの同期操作だけで、待ち合わせ・sleep・タイミング依存を持たない（`FileWatcherStartsOffCallerThreadTests` はソース走査、`FileFingerprintTests` は stat の比較）。

## 実機での部分確認（2026-08-30 / 高速なローカルパス）

worktree のビルド（`BefoldApp/.build/xcode/Build/Products/Debug/befold.app`、`ps` で起動パスを確認）を立ち上げ、`sample <pid> 3` を撮りながら別ファイルを `open -a` で開いた。

結果: メインスレッドのサンプル 2118 件中、`open()` に居るものは **0 件**。FileWatcher / startMonitors のフレームもメインスレッドに現れない。

**これは高速なローカルディスク上での測定であり、AC #3 が求める「遅いパスで固まらないこと」の確認ではない。** 高速なパスでは `open()` が一瞬で終わるため、修正前でもサンプルに写らない可能性がある（＝この測定は修正の有無を区別しない）。証拠として言えるのは「ファイルを開く経路でメインスレッドが syscall に入っていない」ことまで。

遅いパスでの確認（上の 4 手順）は**未実行のまま**。iCloud Drive の dataless ファイルやネットワークボリュームを用意できていない。TCC ダイアログを伴う経路（~/Desktop 等）でも再現しうるが、ユーザーのプライバシー設定を変える操作になるため実行していない。
<!-- SECTION:NOTES:END -->
