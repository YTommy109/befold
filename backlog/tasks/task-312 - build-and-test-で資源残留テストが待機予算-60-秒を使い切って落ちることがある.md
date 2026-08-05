---
id: TASK-312
title: build-and-test で資源残留テストが待機予算 60 秒を使い切って落ちることがある
status: Done
assignee:
  - '@claude'
created_date: '2026-08-05 03:15'
updated_date: '2026-08-05 05:32'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 510000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
実測: CI run 30962672970 の build-and-test で GitCommandRunnerResourceLeakTests の "殺し切れない孫が標準出力を握っていてもスレッドと fd は返る" が `waitUntil が 60.0 seconds 以内に条件を満たさなかった`(GitCommandRunnerTests.swift:475) で失敗した。TSan 側の恒常失敗(.timeLimit の直書き)とは別で、こちらは打ち切りではなく**ポーリング予算そのものの枯渇**。

背景として、このスイートは 1105 テスト並列の輻輳を強く受ける。同一 run では無関係なテストが揃って 13.0〜13.5 秒・24.5 秒といった同値の所要時間を報告しており、テストの所要時間がスイート全体の wall time に張り付いている(別調査で、@MainActor テストが `GitTestRepo.run` の `Process.waitUntilExit()` で main actor をブロックしながら git を起動するため、main actor が長大な直列キューになることを実測済み)。したがって「fd/スレッドが返るまで」の観測が 60 秒に収まらない事象は輻輳次第で再発しうる。

判断が必要なのは、これを (a) 予算(`BEFOLD_TEST_TIMEOUT_SECONDS`, ci.yml の build-and-test 既定 60)の引き上げで吸収するのか、(b) 資源解放が本当に遅い実装上の問題として扱うのか。単発観測のため、まず再現頻度の確認から。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 当該テストの失敗が輻輳由来か実装由来かを、再実行またはログの実測で切り分けている
- [x] #2 切り分けの結論と、予算・直列化・判定条件のどこで吸収するかの決定を、根拠付きで Notes に残している
- [x] #3 判定を「このランナーが開いた pipe が閉じたか」に変え、実装を意図的に壊すと失敗し通常は通ることを実測で確認している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 切り分け実測 (AC#1)

**CI 実測 (run 30962672970 build-and-test)**
- 当該テストは 62.234 秒で失敗、テスト run 全体は 74.289 秒 (1094 tests / 162 suites)。
- テスト開始 00:17:15.469、失敗 00:18:09.790 (= run 終了の 0.001 秒前)。run 終盤の 54 秒はこのテストの待機だけが残っていた。
- 直近 20 run のうち build-and-test の失敗はこの 1 回のみ。他の failure はすべて thread-sanitizer (task-311 / PR#408 で解消済みの別件)。

**ローカル実測**
- `swift test --filter GitCommandRunnerResourceLeakTests` 3 回: いずれも当該テスト 2.6 秒で pass。
- `BEFOLD_TEST_TIMEOUT_SECONDS=60 swift test` (フルスイート 1109 tests) 1 回: 当該テスト 2.647 秒で pass、全体 18.164 秒。

**コード実測 (GitCommandRunnerTests.swift / GitCommandRunner.swift)**
- 失敗箇所 :475 は `waitUntil(timeout: budget) { openPipeCount() <= baselinePipes }`。
- `openPipeCount()` (:110-119) は `0..<getdtablesize()` を全走査して `S_IFIFO` を数える **プロセス全体**の計数。baseline は :462 でスナップショット 1 回。**slack ゼロ**。
- 隣接テスト `repeatedTimeoutsDoNotAccumulateResources` (:447) は同じ計測に `slack = 3` を許している。
- `@Suite(.serialized)` はスイート内の直列化のみで、他スイートとの並走は許容される (:274-278)。
- 一方 `readerThreadCount()` (:125-144) はスレッド名 `"GitCommandRunner.read"` でフィルタしており、**自分の資源にスコープされている**。
- 被テスト側で fd が返るトリガーは EOF ではなく読み取りスレッドの期限 (`timeout + terminationGrace` = 2.0 + 0.5 秒) 満了 → スレッド退出 → `Pipe` の ARC 解放。明示 close はない (:155-157 に理由コメント)。したがって実装上の解放所要は約 2.5 秒で、60 秒を要する余地はない。

**結論**
輻輳による「遅延」でも実装の「解放遅れ」でもない。**テストの計測設計由来**と判断する。プロセス全体の pipe fd 数を slack ゼロで baseline と比較しているため、baseline サンプリング後に他スイートのテストが pipe を 1 本でも開いて保持し続けると、条件は以後 **恒久的に成立しなくなり**、予算を使い切って落ちる。62 秒フルに使って落ち、遅れて成功しなかったという挙動はこの「恒久オフセット」と整合する (輻輳による遅延なら予算内のどこかで成立するはずで、実際 run 終盤 54 秒は他テストが出払っていた)。

したがって AC#2 の選択肢のうち **予算 (`BEFOLD_TEST_TIMEOUT_SECONDS`) の引き上げでは直らない**。判定条件側を直す必要がある。

## 検討と実装 (AC#2, AC#3)

### 単純化の検討

先に判定条件を減らす方向を検討した。

- 案A「pipe 計数を撤去しスレッド計数のみ」: fd 解放のトリガーはスレッド退出 → `Pipe` の ARC 解放しかないため、二重に測っているとも言える。ただし「スレッドは抜けたが `Pipe` が別所参照で残り fd が返らない」種の回帰を検出できなくなる。`GitCommandRunner.swift:153-157` が「読み取り端を明示 close せず ARC 解放に任せる」ことを意図的な設計判断として宣言しているため、その前提が崩れる変更を捕まえる価値があると判断し不採用。
- 案B「slack を隣接テストと同じ 3 にする」: 誤爆を減らすだけで、汚染が 4 本になれば同じ形で再発する。今回の実測が「恒久オフセットは予算では救えない」ことを示した以上、閾値を足す方向は同じ罠の再演になるため不採用。
- 案C「pipe の inode 集合の差分で自分の pipe を同定」: 実装前に前提検証したところ**効かない**ことが判明。macOS の pipe は端ごとに一意な inode を持つ(実測)ので同定自体は可能だが、問題は同定ではなく**帰属**で、「基準線の後に増えた pipe」には他スイートの pipe も等しく入る。しかも現行の `count <= baseline` も汚染源が閉じれば成立するので、集合差と自己修復の挙動が同じ。改善量はほぼゼロのため不採用。

### 採用した形

`readerThreadCount()` がスレッド名で対象を絞れているのは、`GitCommandRunner.swift:150` の `reader.name = "GitCommandRunner.read"` という**本番コード側の観測点**があるため。同じ手を pipe にも入れて帰属を成立させた。

- `GitCommandRunner.init` に `pipeObserver: (@Sendable (Int32) -> Void)? = nil` を追加し、`Pipe()` 生成直後に読み取り端の fd を通知する(`GitCommandRunner.swift:114`)。`timeout` / `terminationGrace` と同じ DI 形式で、グローバル可変状態を作らない。
- テスト側は通知された fd を `fstat` して `(fd, st_ino)` の組 `PipeIdentity` を控え、**その同一性が消えること**を待つ。fd 番号だけだと再利用で別物を掴むが、inode まで見れば「あの pipe そのもの」を指せる。他スイートが何本開いても判定に入らない。
- 空成立の防止として `try #require(observed.get(), ...)` で「ランナーが開いた pipe を観測できていた」ことを固定。

`repeatedTimeoutsDoNotAccumulateResources` は今回の失敗報告の対象外なので手を付けていない(`openPipeCount()` はそちらで引き続き使用)。同種の潜在的脆さは残るが、20 ラウンド積み上がる形なので検出マージンが大きく、優先度は低い。

### 実測

- 正常時: `swift test --filter GitCommandRunnerResourceLeakTests` で当該テスト 2.584 秒 pass。
- フルスイート `BEFOLD_TEST_TIMEOUT_SECONDS=60 swift test` = 1109 tests / 163 suites all pass (18.636 秒)、当該テスト 2.614 秒。
- **回帰検出の確認**: `deadline` を `timeout + terminationGrace` から 86400 秒へ意図的に壊すと、pipe 同一性の待機 (:503) とスレッド計数の待機 (:504) の両方が `waitUntil が 30.0 seconds 以内に条件を満たさなかった` で失敗した。判定を変えても検出力は落ちていない。壊した箇所は元に戻し済み。
- swiftlint: main とのベースライン差分は `file_length` の数値変化のみ (GitCommandRunnerTests.swift 479 → 507 行)。違反の種類・ファイルは増えていない (78 件 → 78 件)。
- swiftformat fix モード実行済み、差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
資源残留テストが CI で待機予算 60 秒を使い切って落ちた件を、判定条件側の欠陥として修正した。

原因は輻輳でも実装の解放遅れでもなく、`openPipeCount()` が**プロセス全体**の pipe fd 数を slack ゼロで基準線と比べていたこと。基準線を採った後に他スイートが pipe を 1 本開いて保持し続けると条件は恒久的に成立しなくなるため、予算を延ばしても直らない形の失敗になっていた(CI ログ: テストが 62.234 秒で失敗、run 全体 74.289 秒、終盤 54 秒は他テストが出払っていた)。

`GitCommandRunner.init` に `pipeObserver` を追加して自分が開いた pipe の読み取り端 fd を通知させ、テストは `(fd, st_ino)` の同一性が消えることを待つ形に変えた。読み取りスレッドに名前を付けて計数対象を絞っているのと同じ手法を pipe にも適用した形。

検証: フルスイート 1109 tests pass、当該テスト 2.6 秒。`deadline` を 86400 秒へ意図的に壊すと当該待機が失敗することを確認し、検出力が落ちていないことを実測した。swiftlint は main 比で新規違反ゼロ(file_length の行数変化のみ)。
<!-- SECTION:FINAL_SUMMARY:END -->
