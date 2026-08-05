---
id: TASK-262
title: analytics ダッシュボードの集計表を SSE で更新する
status: Done
assignee: []
created_date: '2026-08-03 11:07'
updated_date: '2026-08-03 11:11'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 454000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布サイトの analytics ダッシュボードで、SSE の新着イベントが「最新イベント」表と種別カウンタにしか反映されず、集計表（日別ダウンロード 14 日 / バージョン別 / 国別 / 参照元別 / OS 別 / 接続元組織別 / ユニーク訪問者）はページをリロードするまで古いままになる。

実測: 2026-08-03 12:45:25 の download が「最新イベント」には出たが「日別ダウンロード（14 日）」には反映されなかった。

原因: site/src/views/dashboard.tsx の STREAM_SCRIPT (22-36 行) が event ハンドラで counter のインクリメントと recent-body への行 prepend しか行っていない。集計表は routes/dashboard.tsx の GET / で summarize() したサーバーレンダリング結果のまま更新されない。

方針（単純化を優先）: クライアント側で各集計表を加算する実装は、JST 日付バケット・上位 N 件の並べ替え・打ち切りといった summarize() の集計ルールを JS に二重実装することになるため採らない。代わりに、新着イベントがあったときだけサーバーが summarize() を再実行し、集計セクションのレンダリング済み HTML を event: summary として流し、クライアントは innerHTML を差し替えるだけにする。これにより集計ロジックは summarize() 1 か所に集約され、既存のカウンタ加算・行組み立ての JS も削除できる。

注意点:
- summarize() の再実行は D1 クエリを伴うため、ポーリングのたびではなく新着イベントを検出したポーリング周期でのみ行う。
- 集計セクション（.totals と .grid）を Dashboard から共通コンポーネントに切り出し、初期レンダリングと SSE 配信で同じものを使う。
- SSE の data 行は改行を含められないため、HTML を JSON.stringify するか改行を除去して送る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 SSE で新着イベントを受信したとき、リロードせずに日別ダウンロード・バージョン別・国別・参照元別・OS 別・接続元組織別・ユニーク訪問者の各集計が更新される
- [x] #2 集計ロジックが summarize() のみに存在し、クライアント JS 側に集計・並べ替えの実装が重複していない
- [x] #3 新着イベントが無いポーリング周期では summarize() を再実行しない
- [x] #4 site/test/dashboard.test.ts に、新着イベント時に summary イベントが配信されることのテストが追加され、既存テストが通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
集計セクションを views/dashboard.tsx の SummarySections に切り出し、初期レンダリングと SSE 配信で共有した。stream ルートは新着イベントを検出したポーリング周期でのみ summarize() を再実行し、renderSummarySections() の HTML を JSON.stringify して event: summary で流す。クライアント JS はカウンタ加算・行組み立てを廃止し #summary の innerHTML 差し替えのみ。site: 50 tests passed / tsc --noEmit clean。
<!-- SECTION:NOTES:END -->
