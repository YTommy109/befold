# フレーキーテスト調査: FileWatcherIntegrationTests（thread-sanitizer ジョブ）

調査日: 2026-07-07

## 概要

CI の `thread-sanitizer` ジョブで `FileWatcherIntegrationTests` が断続的に失敗する。
最頻の失敗は `detectsChangeAfterRecreation()`（`FileWatcherIntegrationTests.swift:91`、
`Confirmation was confirmed 0 times`）。

- 対象 run: <https://github.com/YTommy109/befold/actions/runs/28839962261/job/85531748833>
- ThreadSanitizer の警告（データレース検出）は **一件も出ていない**。純粋にテストのタイミング起因。

## 失敗履歴（直近 20 run 中 4 回失敗、すべて thread-sanitizer ジョブ）

| run | 日時 (UTC) | 失敗テスト |
| --- | --- | --- |
| 28839962261 | 07-07 03:44 | detectsChangeAfterRecreation |
| 28811149695 | 07-06 17:39 | detectsChangeAfterRecreation, detectsAtomicSave, detectsFileDeletion |
| 28802878185 | 07-06 15:25 | detectsChangeAfterRecreation, detectsAtomicSave, saveByRenameIsTreatedAsChangeNotRename |
| 28797558638 | 07-06 14:05 | detectsChangeAfterRecreation, detectsMoveToAnotherDirectory, detectsRenameWithinSameDirectory |

- `detectsChangeAfterRecreation` は **4 回すべて** で失敗しており、最も脆弱。
- 他のジョブ（通常テスト）では失敗しておらず、TSan 環境（5〜15 倍のスローダウン）でのみ再現。

## 根本原因

### 前提: 実行環境の条件

1. **Swift Testing はスイート内のテストを並列実行する**。ログ上、
   FileWatcher 系 8 テストが同時刻（03:45:44.25）に一斉開始している。
   各テストが FileWatcher（GCD キュー + DispatchSource + Debouncer タイマー）を持ち、
   TSan の計装で遅くなった少コアの CI ランナー上でリソースを奪い合う。
2. テストは `Task.sleep` による **固定の実時間スリープ** でイベント伝搬を待っている。

### 失敗モード 1: 監視再開レースによる恒久的な取りこぼし（detectsChangeAfterRecreation）

このテストの流れと時間予算:

```
0.3s 待ち → 削除 → 0.5s 待ち → 再作成 → 0.5s 待ち → armed=true → 書き込み(1回) → 3s 待ち
```

`FileWatcher` はファイル削除でファイル監視ソースを解放し、
親ディレクトリ監視（`.write` イベント）で再作成を検知して
`startFileMonitor()` で監視を再開する設計（`FileWatcher.swift:188-194`）。

問題は、**再作成 → 監視再開の完了** が固定 0.5 秒以内に終わる保証がないこと。
TSan スローダウン + 8 テスト並列の負荷でディレクトリイベント配送や
監視キュー上の `startFileMonitor()` 実行が遅れると、
テストが 1 回だけ行う最終書き込み（`atomically: false` の内容変更）の時点で
ファイル監視がまだ張られていない。

**内容のみの書き込みはディレクトリの `.write` イベントを発生させない**ため、
監視再開が間に合わなかった場合、この変更を検知するイベントは永遠に来ない。
その後 3 秒待っても回復不能で `confirmed 0 times` になる。
このテストが 4 回全部で失敗している（他はたまに失敗）のはこのためで、
他のテストは `waitUntil` ポーリングで「遅れ」を吸収できるが、
このテストの失敗モードは「遅れ」ではなく「イベントの喪失」だから。

### 失敗モード 2: 単純なタイムアウト超過（その他のテスト）

`detectsAtomicSave` / `detectsFileDeletion` / `saveByRenameIsTreatedAsChangeNotRename` /
`detectsRenameWithinSameDirectory` / `detectsMoveToAnotherDirectory` は
`waitUntil`（タイムアウト 5 秒）で待つが、高負荷時は

- カーネルイベント配送 → 監視キュー上のハンドラ実行
- Debouncer の 0.2 秒タイマー（`renameSettleDelay` 経由だとさらに +0.2 秒）
- `Task { @MainActor }` への hop（並列テストで MainActor が混雑）

の合計が 5 秒を超えることがあり、タイムアウトで失敗する。
成功時ですら各テストが 4.6〜5.0 秒かかっており（ログ参照）、余裕がほぼない。

### プロダクトコードへの影響

プロダクト設計上も「再作成の通知（この時点で最新内容を再読込）から
ファイル監視再開までの間」に発生した内容のみの書き込みは取りこぼす
理論上の窓が存在する。ただし実運用ではこの窓は数ミリ秒であり、
続けて保存すれば検知されるため、実害は小さい。修正必須ではない。

## 対策案（推奨順)

以下はいずれも 2026-07-11 に実装済み（詳細は「追加対策（2026-07-11）」を参照）。

1. **detectsChangeAfterRecreation を「1 回書き込み + 固定待ち」から
   「発火するまで書き込みをリトライするループ」に変更する**（実装済み）。
   監視再開が遅れてもその後の書き込みで検知でき、失敗モード 1 が解消する。
   固定スリープ全般を条件ベース待機に置き換える
   （superpowers の condition-based-waiting パターン）。
2. **`@Suite(.serialized)` を付与して FileWatcher 系テストを直列化する**（実装済み）。
   TSan 環境での CPU 競合と MainActor 混雑が減り、失敗モード 2 が緩和する。
   直列化で総時間は延びるが、各テスト 5 秒弱 × 8 本で 40 秒程度に収まる。
   （実測では遅延パラメータ化と併せて非 TSan ローカルで約 7.2s → 約 2.5s に短縮した。）
3. （補助）`waitUntil` のタイムアウトを TSan ジョブ向けに延長する（実装済み）。
   環境変数 `BEFOLD_TEST_TIMEOUT_SECONDS` で上書き可能にし、CI の
   thread-sanitizer ジョブで 30 秒に設定した。

## 追加対策（2026-07-11）

<!-- derived-from #対策案推奨順 -->

上記の対策案に加えて、決定性の向上とタイミング依存の削減を目的に次を実施した。

1. **ViewerStore への Clock 注入によるグレース期間テストの決定的化**（コミット 2f67d15）。
   削除確定のグレース期間（1 秒）を仮想時刻で駆動できるようにし、
   `ViewerStoreFileGoneTests` の実時間依存を排除した。

2. **FileWatcher の遅延パラメータ化**。
   `debounceDelay`（既定 0.2s）と `renameSettleDelay`（既定 0.2s）を `init` 引数化した。
   プロダクト呼び出し元は既定値のまま無変更。統合テストは短い値（0.05s）を注入して、
   伝搬チェーンの所要時間と TSan 下のマージンを改善する。

3. **実 FS 統合テストの「発火するまで書き込みリトライ」パターン統一**。
   `waitUntilWithRetry` を `TestSupport.swift` の共通ヘルパーへ昇格し、MainActor 版
   `waitUntilWithRetryOnMainActor` を追加した。書き込み系（冪等な操作）のテストは
   リトライ型に変更してイベント取りこぼしに強くした。delete / rename / move 系は
   アクションが冪等でないためリトライ化せず、代わりに 4 の arm 確認プローブを併用する。

4. **監視 arm 確認プローブの導入（当初の「init 待ち sleep は不要」判断の訂正）**。
   当初は「`FileWatcher.init` が `queue.sync { startMonitors() }` で同期的に監視開始を
   完了するため、初期化待ち sleep は不要」と判断して各テスト冒頭の
   `Task.sleep(for: .seconds(0.3))` を削除した。**これは誤りだった**。
   `DispatchSource.resume()` は同期的に戻るが、kqueue の kevent 登録は dispatch の
   マネージャスレッドで**非同期**に完了する。つまり init 完了とイベント受信可能は同義でなく、
   登録前に発生したエッジトリガーのイベント（`.delete` / `.rename`）は永遠に失われる。
   前回削除した sleep はこのレースを偶然隠していた。PR #171 の CI（build-and-test,
   macos-26, run 29135997742）で `detectsFileDeletion` と
   `deletingWatchedFileFiresOnFileGone` が waitUntil タイムアウトで失敗し、
   書き込みリトライ系が全て通ったことと整合する。
   対策として、sleep を復活させるのではなく条件ベースの arm 確認プローブ
   `confirmWatcherArmed`（`TestSupport.swift`）を導入した。対象ファイルへ
   `atomically: false` の書き込みを繰り返して最初のコールバック到達を待ち、file source の
   kevent 登録完了を観測する（`atomically: true` は rename 経由で監視を張り直し登録レースを
   再発させるため使わない）。その後、プローブ書き込みのデバウンス残コールバックが検証を
   汚さないよう、コールバック数が一定時間（0.3s = テスト用 debounce 0.05s の 6 倍）
   増えなくなるまで静穏化を待ち、静穏化後のカウントを基準値として「操作後の発火」を
   `count > baseline` で判定する。削除・rename・move・save-by-rename・再作成前削除の
   各テストに適用した。`ViewerStoreIntegrationTests.deletingWatchedFileFiresOnFileGone`
   では content 更新の観測で arm を確認する（content 更新は onFileGone に影響しないため
   静穏化不要）。この arm 確認により、`saveByRenameIsTreatedAsChangeNotRename` が
   rename イベント喪失時に `renamed == nil` を偽陽性でパスする問題も解消する。

5. **TSan 実行時のタイムアウト延長**。
   `waitUntil` / `waitUntilOnMainActor` の既定タイムアウトを
   `BEFOLD_TEST_TIMEOUT_SECONDS` で上書き可能にし、`.github/workflows/ci.yml` の
   thread-sanitizer ジョブに `BEFOLD_TEST_TIMEOUT_SECONDS: 30` を設定した。

6. **`ViewerStoreIntegrationTests` の直列化**。
   実 FS + 実 FileWatcher を使うため `@Suite(.serialized)` を付与し、
   短い debounce を `watcherFactory` 経由で注入するよう変更した。

## 参考

- 失敗ログ抜粋（初回調査時）: `Test detectsChangeAfterRecreation() recorded an issue at
  FileWatcherIntegrationTests.swift:91:28: Confirmation was confirmed 0 times,
  but expected to be confirmed 1 time`
- arm 登録レースの再現: PR #171 build-and-test（macos-26）run 29135997742 で
  `detectsFileDeletion` / `deletingWatchedFileFiresOnFileGone` が失敗
- 関連コード: `BefoldApp/befold/FileWatching/FileWatcher.swift`
  （`startDirectoryMonitor` / `startFileMonitor` / `Debouncer 0.2s`）
- テスト: `BefoldApp/befoldTests/FileWatcherIntegrationTests.swift`
