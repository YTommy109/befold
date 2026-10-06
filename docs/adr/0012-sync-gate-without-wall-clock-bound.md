# ADR 0012: 同期ゲートの待機は壁時計の上限を持たず、塞いでよいスレッドかを実行時に検査する

- ステータス: Accepted
- 日付: 2026-10-06
- backlog decision: decision-13
- 関連タスク: TASK-674（発端は TASK-619 / TASK-665 / TASK-672）

<!-- constrained-by ../dev/native-app-design.md#mainactor-の外へ逃がす処理は-withblockingwork-を通す -->

## Context

テストのフェイクは「遅い実装」を演じるとき、同期ゲート `BlockingGate`
（`BefoldApp/BefoldTestSupport/BlockingWait.swift`）で呼び出しスレッドを塞ぐ。
この待機には壁時計の上限があり、超えると失敗を記録して戻る。

この上限が、正しいテストを 3 週間に 3 回落とした。

| タスク | 発生日 | 実行 | 上限 |
| --- | --- | --- | --- |
| TASK-619 | 2026-09-13 | CI の通常テスト | 60 秒 |
| TASK-665 | 2026-09-29 | 手元の並列実行 | 15 秒 |
| TASK-672 | 2026-10-06 | CI の thread-sanitizer | 120 秒 |

3 件とも型は同じである。ゲートを開けるのはテスト本体で、開けるまでに MainActor の
順番待ちを通る。全テストはほぼ同時に始まり MainActor で直列化されるため、順番待ちは
run 全体の長さに応じて伸びる。上限が測っていたのは、模した処理の遅さではなく
この順番待ちだった。

対処は 3 件とも個別で、型は残った。TASK-619 は上限を 300 秒へ延ばした。TASK-665 は
1 つのテストを async のゲートへ移した。TASK-672 は 1 つのフェイクだけ上限を外した。

### 上限があった理由

上限は TASK-424 の対策として入った。当時のフェイクは協調スレッドプールの上で
塞いでいた。上限が無いとプールが埋まり、テストプロセス全体が止まった。

その後、プールを守る役目は別の仕組みへ移った。

- 本番コードは、塞ぐ処理を `withBlockingWork`（`BefoldApp/BefoldKit/BlockingWork.swift`）の
  専用スレッドへ逃がす
- `scripts/check-no-detached-blocking.sh` が `Task.detached` を弾く
- CI は協調プールの幅を 1 に絞ったレッグでも全件を回す

async 側の待機は、既に上限を持たない。`AsyncGate` と `waitForMainActorDelivery`
（`BefoldApp/BefoldTestSupport/Waiting.swift`）は、戻らない回帰の打ち切りを
`.timeLimit` に委ねている。理由は同じで、壁時計の上限が順番待ちを測ってしまうためである。
壁時計の上限が残っていたのは同期ゲートだけだった。

### 現状（実測 / 2026-10-06 時点）

フェイクが同期に塞ぐ箇所は 6 つある。コードを読んで経路を辿った結果、待つスレッドは
6 箇所とも専用スレッドだった。

| テストスイート | 開けるまでの順番待ち | 上限 |
| --- | --- | --- |
| `GitStatusStoreTests` | MainActor への復帰が 2 回 | 固定 300 秒 |
| `GitCommandFileIndexConcurrencyTests` | 協調プール上のポーリング | 環境変数 |
| `ViewerWindowControllerDiffTests` | なし | 環境変数 |
| `BlockingWorkTests` | 協調プール上のポーリング | 環境変数 |
| `ViewerWindowManagerRecentRepositoriesTests` | なし | 環境変数 |
| `ViewerRendererRenderRaceTests` ほか 1 スイート | MainActor への復帰 | なし |

3 件と同じ型の露出が残るのは `GitStatusStoreTests` である。TASK-672 の run は全体が
363 秒かかっており、300 秒の上限を超えうる。

6 箇所とも、フェイクが準拠するプロトコルは同期である。本番側に async の注入点は無い。

上限は 2 つの役を兼ねていた。

- **足止め**: テスト本体が開けに来るまで塞ぐ。待ち時間は順番待ちで決まる
- **退行の検出**: 正しい実装では待たない。本番が退行すると、メインスレッドか
  協調プールで待つことになり、開ける者に順番が回らないので上限で失敗する。
  `ViewerWindowControllerDiffTests` と `BlockingWorkTests` がこの役で使う

## Decision

**同期ゲートの待機は壁時計の上限を持たない。代わりに、閉じたゲートをメインスレッドか
Swift Concurrency のタスクの上で待とうとしたら、塞がずに失敗を記録して戻る。**

- 待機の API は 1 つにし、秒数を引数に取らない。環境変数 `BEFOLD_TEST_TIMEOUT_SECONDS` も
  参照しない。呼び出し側が上限を選べないので、同じ型のテストは書けない
- 塞いでよい場所かは `Thread.isMainThread` と `withUnsafeCurrentTask` で判定する。
  どちらも公開 API である。協調スレッドプールで走るコードはタスクの上にあるので、
  後者で捕まる
- `ViewerWindowManagerRecentRepositoriesTests` は足止めを `DispatchSemaphore` で書いている。
  これも `BlockingGate` へ移し、セマフォで足止めを書く箇所を 0 にする
- 戻らない回帰の打ち切りは、async 側と同じく `.timeLimit` に委ねる

上限が兼ねていた 2 つの役は、こう分かれる。足止めは上限なしの待機が担う。
退行の検出は場所の検査が担う。

### 決定を支える実測（2026-10-06）

待機を上限なしにして場所の検査を足す一時的な変更を当て、手元の macOS 27 で測った。

- 全体実行で、既存の 1998 テストは通常の設定でもプール幅 1 でも pass した。
  既存の待機に対する検査の誤発火は 0 件だった
- 検査は協調プール上のタスク、MainActor 上のテスト本体、メインキューのコールバックで
  発火した。専用スレッド上では発火しなかった
- `ViewerWindowControllerDiffTests` へ退行を注入すると、テストは 1.1 秒で失敗した。
  注入したのは、ルート解決を MainActor 上で同期に呼ぶ変更である。
  失敗にはテスト名が付いた

### 採らなかった案

**async の注入点へ移して `AsyncGate` で待つ**（TASK-665 の方式）。既存の注入点が
1 つも無く、同期プロトコルを 4 つ async にする本番変更が要る。
`GitCommandFileIndexConcurrencyTests` はロックの粒度を測っており、`BlockingWorkTests` は
同期に塞ぐこと自体を測っている。この 2 つは async にするとテストの意味が消える。
また、新しいテストが上限付きの待機を使うことは止められない。
async の注入点が既にある箇所では、引き続き `AsyncGate` を先に選ぶ。

**上限付きの待機を検査スクリプトで禁止する**。禁止したいのは「開ける側が MainActor の
順番に依存する」使い方だけである。これは、足止めから解放までの間に `await` があるかを
読まないと決まらず、grep では判定できない。API から上限を消せば、コンパイルで止まる。

**thread-sanitizer のジョブを一部のスイートへ絞る**。3 件のうち 2 件は thread-sanitizer
以外の実行で起きた。データ競合を検出できる範囲も減る。

**上限を延ばす**（TASK-619 の方式）。混雑が上限を超えれば同じ失敗になる。

**塞いでよい場所かを libdispatch のキューラベルで判定する**。実測では、協調プールの
ラベルは `.cooperative` で終わり、専用スレッドと区別できた。ただしラベルの命名は
公開された仕様ではない。公開 API の `withUnsafeCurrentTask` で同じ判定ができる。

## Consequences

- 混雑は遅延になるだけで、失敗にならない
- 退行の検出が上限を待たなくなる。従来は環境変数の上限（既定 15 秒）まで待っていた
- ゲートを開け忘れたときの見え方が変わる。実測した結果は次のとおりである
  - テストが結果を待たなければ、何も起きない。専用スレッドが 1 本残るだけで、
    テストは pass した
  - テストが結果を待つと、`.timeLimit` がテスト名つきで失敗を記録する。ただし run は
    終わらない（打ち切り 60 秒に対し、300 秒まで終わらないことを確認した）。
    CI ではジョブの制限時間まで続く
  - これは書き間違えた時点で毎回起きる。混雑に左右される失敗ではない
- 検査が効くことは、検査自身のテストで守る。CI の macos-26 と thread-sanitizer の下での
  挙動は未確認で、このテストが最初の確認になる
- `DispatchQueue.global()` 上の待機は検査に掛からない。タスクの上ではないためである。
  ワーカーの数がコア数で頭打ちになるので塞ぐべきでない場所だが、
  現状ここで待つフェイクは無い
- フェイクが `DispatchSemaphore` などで上限付きの足止めを自作することは止めない。
  3 件はすべて `BlockingGate` を通っており、自作の足止めは移行後に 0 箇所になる
- テスト本体が上限つきで待つ箇所は対象にしない。`ViewerStoreLoadStartTests`、
  `FileWatcherSlowOpenTests`、`BefoldCLIIntegrationTests` がこれにあたる。
  待つ相手が MainActor を通らないため、型が異なる

### 再検討する条件

開け忘れによる「終わらない run」が CI で起きたら、ゲートに自己解放を足す。
自己解放の時間は `.timeLimit` と同じ定数にし、呼び出し側が選べない形にする。

上限付きの足止めを自作するフェイクが再び現れたら、検査スクリプトで弾く。
