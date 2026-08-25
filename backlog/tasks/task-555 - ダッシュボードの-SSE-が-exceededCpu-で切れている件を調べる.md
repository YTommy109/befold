---
id: TASK-555
title: ダッシュボードの SSE が exceededCpu で切れている件を調べる
status: To Do
assignee: []
created_date: '2026-08-25 02:33'
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
- [ ] #1 exceededCpu が恒常的か一時的かが実測で判別できている
- [ ] #2 恒常的なら 1 invocation あたりの CPU を下げる方針が決まり、実施されている
- [ ] #3 observability の cpuTimeMs が invocation 合計かスライスかが確認できている
<!-- AC:END -->
