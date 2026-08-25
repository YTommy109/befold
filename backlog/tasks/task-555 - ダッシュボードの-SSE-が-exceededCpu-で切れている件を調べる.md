---
id: TASK-555
title: ダッシュボードの SSE が exceededCpu で切れている件を調べる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-25 02:33'
updated_date: '2026-08-25 02:51'
labels: []
dependencies:
  - TASK-554
priority: high
type: bug
ordinal: 803000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
本番の Workers observability（2026-08-18〜08-25 の 7 日間）を見ると、Worker `befold` の全 2,041 invocation のうち **714 件が `exceededCpu` で終了しており、その 714 件すべてが `GET /dashboard/stream`**（TASK-554 の調査で発見）。

## 実測（2026-08-25 / 直近 7 日 / observability の calculations ビュー）

| outcome | 件数 | 平均 CPU | 平均 wall |
|---|---|---|---|
| ok | 185 | 274 ms | 598 s（= MAX_STREAM_MS の 10 分を完走） |
| exceededCpu | 714 | 11.6 ms | 17〜30 s |
| canceled | 25 | 80 ms | 152 s |

- `exceededCpu` の 714 件は **2026-08-21 15:12〜23:36 のおよそ 9 時間に集中**している（他の日は 0 件）。
- その窓では平均 CPU 11.6 ms で落ちており、**1 invocation あたり 10 ms の CPU 上限**が効いているように見える（Workers Free の既定値と一致する）。一方、他の日の `ok` は 274 ms（最大 461 ms）を使って完走しているので、恒常的に 10 ms 上限が掛かっているわけではない。
- `site/wrangler.toml` に `[limits]` / `cpu_ms` の指定は無い（grep 済み）。同期間に site/ のデプロイに当たるコミットも無い。

## 分からないこと

- なぜその窓だけ 10 ms 相当で切られたのか。プランの一時的な扱い、Cloudflare 側の変更、あるいは observability の `cpuTimeMs` の意味（invocation 合計か、ログイベント単位のスライスか）の解釈違いが考えられる。
- ユーザー影響: EventSource は自動再接続するため、切れても画面は動き続ける（`/stream` の catch は静かに閉じる）。したがって**気づかないまま再接続を繰り返している**可能性がある。

## やること

- `cpuTimeMs` の意味を確定させる（同じ invocation の複数ログか、1 件で invocation 合計か）。
- 再発しているかを継続観測する（invocations ビューで `outcome=exceededCpu` を追う）。
- 恒常的に起きるなら、1 周期あたりの CPU を下げる（新着があった周期に概要面 HTML を丸ごと再描画している `runStreamCycle` が主因の候補）か、`MAX_STREAM_MS` を縮めて 1 invocation あたりの累積 CPU を下げる。

## 背景

TASK-554（SSE を DO 経由の push へ切り替えられるか）の調査で、コストを実測する過程で発見した。554 側の結論は「DO は不要」で、この件はそちらのスコープ外。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 exceededCpu が恒常的か一時的かが実測で判別できている
- [x] #2 恒常的なら 1 invocation あたりの CPU を下げる方針が決まり、実施されている
- [x] #3 observability の cpuTimeMs が invocation 合計かスライスかが確認できている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 方針: 再開位置をクライアントへ必ず伝える（1 周期 1 ブロック）

ポーリング 1 周期の末尾に出している `: keep-alive` コメントを、`id: <nextLastId>` を伴う `event: cursor` ブロックへ置き換える。バイトを流し続ける keep-alive の役割はそのまま兼ね、EventSource の `Last-Event-ID` が毎周期 nextLastId まで進む。これにより、再接続時の `arrived` 判定が「ページを開いた時刻からの差分」ではなく「前の周期からの差分」になり、重い経路（summarizeOverview 4 本 + 概要面の全再描画、実測 9.5 ms/回）が接続のたびに走らなくなる。

1. `site/src/routes/dashboard.tsx` の SSE ループ: keep-alive を cursor ブロックへ置き換える。**順序は events → summary → cursor を厳守**（下の設計レビュー 5 を参照）
2. `site/test/dashboard.test.ts`: 4 つの SSE テストが周期の終端センチネルに 'keep-alive' を使っているので 'event: cursor' に替える
3. 回帰テストを 2 本足す: (a) ロボットしか来なかった周期でも `id:` がその行の id まで進む、(b) 新着の無い周期でも毎周期 `id:` が出る（= 再接続位置が古いまま固まらない）

## 設計レビュー（/review-design、実装前に 1 回実施）

1. **判定の真実の源**: `arrived = latestId > lastId` は生の最大 id（ロボット込み）という事実で判定していて、データの中身の有無では判定していない。この述語自体は変えない。当初案は「data を持たない `id:` だけのブロックでも lastEventId は進む」という SSE 仕様の細部に依存していたが、ブラウザ実装差を踏み込んで確かめられないため、**data を持つ `event: cursor` にして仕様の解釈に依存しない形へ変更した**
2. **既存の不変条件との衝突**: 「カーソルは生の最大 id で進める（ロボットを除かない）」（`runStreamCycle` の doc）に、クライアント側のカーソルも初めて揃う。今は server だけがこの不変条件を守り、client は人間のイベントでしか進まない状態で、その食い違いが今回のバグ
3. **消費経路の全列挙**: 再開位置を読む箇所は `/stream` の `resumeFrom`（`Last-Event-ID` → `?after=` → 0）の 1 箇所のみ。書く箇所は SSE の `id:` 行のみ。`data-last-id` は初回接続専用（`rg 'lastId|last-id' site/src` で確認済み、該当 3 箇所）。兄弟判断として「新着があったか」を判定する箇所は `runStreamCycle` の `arrived` だけ
4. **新しい状態に対応する表示**: cursor イベントにクライアント側のリスナは付けない（EventSource は未知の event 型を無視する）。画面の表示状態は増えない
5. **ライフサイクル・順序**: cursor は**その周期の events と summary を送り切った後**に出す。先に出すと、cursor 送信後・summary 送信前に切断された場合に、再接続側が「その周期は処理済み」と見なして概要の更新を 1 回落とす
6. **高頻度経路のコスト**: 1 周期あたり 30 バイト程度のブロックが 1 つ増えるだけ（アイドル周期の実測 0.9 ms に対して無視できる）。狙いは逆に、9.5 ms の重い経路の実行回数を減らすこと
7. **測るものと守るものの一致**: サーバ側で固定できるのは「毎周期 `id:` が nextLastId で出る」ところまで。**ブラウザが再接続時にその値を `Last-Event-ID` で送り返すかは vitest では測れない**（EventSource の実装依存）。この 1 点は未検証として Notes に残す
8. **非同期で置き換わる表示状態の世代管理**: 該当しない。表示の差し替えは summary の innerHTML 置換 1 経路のみで、対象の切り替えが無い
9. **決めた粒度を守らせるもの**: 「再開位置は毎周期クライアントへ伝える」を破ったら落ちるテストを上の 3 で用意する（doc コメントだけにしない）
10. **型グループの行数**: Swift 向けの項目で該当しない。`site/src/routes/dashboard.tsx` は 263 行、増分は数行
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 調査（2026-08-25）

### 起票時の記述の訂正: 「2026-08-21 の 9 時間に集中」は誤り

observability に渡した相対 timeframe の reference を未来の時刻（`2026-08-25T11:40:00Z`、実際の現在時刻は 02:45Z）にしていたため、系列のラベルがずれていた。**バーストは 08-21 に固定ではなく、継続的に再発している。**

- 直近 3 日（08-22 02:45Z 〜 08-25 02:45Z）: ok 89 / **exceededCpu 445** / canceled 11
- 今日（08-25 00:00Z 〜 02:45Z）: ok 13 / **exceededCpu 61** / canceled 2

### 恒常か一時か → 「短時間のバーストが繰り返し起きる」

08-25 のタイムラインが典型:

| 時刻 (UTC) | outcome | 平均 CPU | 平均 wall |
|---|---|---|---|
| 00:04〜01:38 | ok（11 分おきに 1 本） | 233〜348 ms | 601 s（10 分完走） |
| 01:38, 01:40 | canceled | 47 ms | 108 s |
| **01:47〜02:07** | **exceededCpu 61 本**（約 18 秒おき） | **ちょうど 10 ms** | 16 s |
| 02:16〜 | ok に復帰 | 341〜383 ms | 602 s |

同じ `scriptVersion.id`（e0c29148-…）・同じ colo（NRT）・同じ `executionModel`（stateless）。ログには `Worker exceeded CPU time limit.` の error が invocation ごとに 1 件。

### cpuTimeMs は invocation 合計（AC #3）

`count` と `uniq($metadata.requestId)` が outcome ごとに完全に一致した（ok 89/89、exceededCpu 445/445、canceled 11/11）ので、**fetch サマリのログは 1 invocation につき 1 件**で、`cpuTimeMs` はその invocation の合計。スライスではない。なお 1 invocation には他に `Worker exceeded CPU time limit.` の error ログが別レコードとして付く（MCP の events / invocations ビューはこの outcome を持たないレコードで zod 検証に失敗するため、calculations ビューで集計した）。

### 「新着が多くて毎周期再描画していた」は否定された

バーストの窓（01:45〜02:07Z）に本番 D1 へ入ったイベントは **4 件だけ**（`SELECT ... GROUP BY minute` で確認: 01:45 に 2 件、01:46 に 1 件、02:04 に 1 件）。連続到着で毎周期 `summarizeOverview` を回していたわけではない。

### 見つけたコード側の欠陥: 再接続時の再開位置が進まない

- `/stream` の再開位置は `Last-Event-ID` ヘッダ、無ければ **ページ読み込み時に固定された `?after=`**（`data-last-id`）
- `id:` 行を出しているのは `event: event`（＝ `eventsAfter` が返した行）だけ。`eventsAfter` は `HUMAN_ONLY` でロボットを除くので、**ロボットしか来ていない間はクライアントの `Last-Event-ID` が一度も進まない**
- `event: summary` と `: keep-alive` には `id:` が無い
- 結果、10 分で接続が切れて再接続するたび、サーバ側は `arrived = latestId > lastId`（latestId はロボット込み）を**真**と判定し、**毎回いちばん重い経路（`summarizeOverview` 4 本 + 概要面 HTML の全再描画）を接続の 1 周期目で実行する**。ページを開いてからの経過時間が長いほど当たりやすい
- 本番の events は 1,735 行中 **726 行（42%）がロボット**なので、この経路は日常的に踏まれている

### 経路ごとのコスト（実測 / 2,000 行の events で `runStreamCycle` を 10 回平均）

| 周期 | 1 周期あたり |
|---|---|
| 新着なし | **0.9 ms** |
| 新着あり（概要面を再描画） | **9.5 ms** |

10 倍差。exceededCpu が記録している 10 ms はこの再描画 1 回ぶんとほぼ同じ大きさで、**「1 バーストが 10 ms を超えると殺される」形と整合する**（アイドル周期を 240 回積んでも 216 ms なので、ok の 233〜383 ms も説明が付く）。

### まだ確定していないこと

Cloudflare 側の CPU 上限が何 ms で効いているのかは外から確定できない。ok の invocation が 383 ms を使えている一方でバースト中は 10 ms で殺されており、同一スクリプト・同一 colo で 38 倍の差がある。Workers のプランも `/user/subscriptions` に `workers_paid` の行が無い（TASK-554 参照）。**ただし対策の向きはプランに依らない**——再接続のたびに最も重い経路を通る構造自体が問題で、それを直せばバーストの起点が消える。

## 対処（実装）

再接続のたびに重い経路を通る構造を直した。**1 周期の末尾に出していた `: keep-alive` コメントを `id: <nextLastId>` を伴う `event: cursor` ブロックへ置き換える**（接続維持の役も兼ねるので、仕組みは 1 つのまま増えていない）。これでロボットしか来ない間もクライアントの `Last-Event-ID` が毎周期進み、再接続時の `arrived` 判定が「ページを開いた時刻からの差分」ではなく「前の周期からの差分」になる。

- 順序は **events → summary → cursor** を厳守（cursor を先に出すと、summary が届かないまま切れた周期を再接続側が処理済みと見なす）
- `data:` を付けたのは、data の無いブロックで `Last-Event-ID` が進むかがブラウザ実装依存のため。クライアントはこの event 型にリスナを付けない（EventSource は未知の型を無視する）
- `site/README.md` に契約として書いた（順序と、`id:` を event 行だけに付けたときに何が起きるか）

## 検証

- `npm test`（site）: 13 files / 431 tests 通過。`npm run lint`（--type-aware）・`format:check`・`markdownlint-cli2` すべてゼロ件
- 追加した回帰テスト 2 本が、実装前は落ちることを確認（先にテストを書いて赤を見た。SSE テスト 6 本が周期終端センチネルの変更でまとめて赤 → 実装後に緑）
- `id: ${lastId}` を `id: 0` に変える変異でも新規 2 本が落ちることを確認（センチネルの一致だけで通ってしまわない）
- クエリ本数は変わらない（`test/query-count.test.ts` は緑のまま）

## 未検証

**ブラウザが再接続時にこの `id:` を `Last-Event-ID` ヘッダで送り返すこと自体は vitest では測れない**（EventSource の実装依存）。本番で確認する方法は、ダッシュボードを開いたまま 10 分以上放置し、observability で `GET /dashboard/stream` の `exceededCpu` が出なくなることを見ること。デプロイ後に TASK-554 の手順（calculations ビューで outcome 別に集計）で追える。

## 副産物: site/README.md の陳腐化を 1 行直した

「ページ別は `page='/'` の「ページアクセス」指標とは別物で、合計は一致しない」は TASK-551 で偽になっていたため、「「/」行は LP への訪問と列の導入前の訪問の和」へ書き換えた。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
原因は Cloudflare 側ではなくコード側だった。SSE が id: を event 行にだけ付けており、eventsAfter がロボットを除くぶん、ロボットしか来ない間はクライアントの Last-Event-ID が進まない。そのため再接続のたびにサーバが「ページを開いた時刻からの差分」を見て、いちばん重い経路（summarizeOverview 4 本 + 概要面の全再描画、実測でアイドル周期の 10 倍）を毎回走らせていた。周期末の keep-alive を id 付きの event: cursor へ置き換えて再開位置を毎周期伝えるようにし、回帰テスト 2 本（変異で落ちることも確認）と README の契約記述を追加した。site の vitest 431 件通過。ブラウザが Last-Event-ID を送り返す点だけはデプロイ後に observability で確認する。
<!-- SECTION:FINAL_SUMMARY:END -->
