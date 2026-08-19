---
id: TASK-534
title: 旧バージョンのダウンロード数が試行回数として過大に積まれるのを直す
status: Done
assignee: []
created_date: '2026-08-19 14:53'
updated_date: '2026-08-19 15:10'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 772000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-533 の調査中に判明した別件。/releases/:tag/:file の archive 計上が、ダウンロードの成否と無関係に積まれる。

- recordEvent が R2 の取得判定より前にある（site/src/routes/public.tsx:138-147）。DIST.get が null で GitHub へ 302 する失敗系でも 1 件残るため、数えているのは「ダウンロード」ではなく「リンクを叩いた回数」。
- R2 ヒット時は immutable 付き 200 でブラウザキャッシュが効く（site/src/routes/public.tsx:182-194）が、R2 に実体の無い旧タグは毎回 302 で毎回 Worker を通るため、同一利用者の再クリックやリトライがそのまま加算される。
- Hono の get は HEAD も拾うため、HEAD・レンジ要求・ダウンロードマネージャの再接続もそれぞれ 1 件になる。
- ボット除去は記録時ではなく集計時の HUMAN_ONLY（UA 接頭辞 + as_org、site/src/analytics.ts:398-449）のみ。/releases は robots.txt で許可されており（site/src/routes/public.tsx:206-212）、表は 1 リリース = 1 リンク（site/src/views/releases.tsx:26-28, 133）なので、UA が普通のブラウザに見えるクローラが全行を辿ると行数ぶんまとめて計上される。

同じ性質が lp / sparkle 側にどこまであるかは未確認。着手時に 3 経路を並べて、どこまで揃えるかを先に決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 archive の計上が、配信に成功した要求だけを数えるようになっている（302 フォールバックの扱いを決めた上で実装する）
- [x] #2 HEAD 要求とレンジ要求の再接続が重複計上されない
- [x] #3 lp / sparkle 経路との計上条件の差を調べ、揃える／揃えないの判断を Implementation Notes に残す
- [x] #4 既存データは遡って直さない方針でよいか判断し、その結論を記録する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. HEAD が GET ハンドラへ流れるかを実測する
2. 3 経路（lp / sparkle / archive）の計上条件の差を調べる
3. 記録の絞り込み点である recordEvent で HEAD を弾く
4. 3 経路すべてを並べたテストで固定する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（vitest + cloudflare:test の使い捨てテストで確認）: Hono は HEAD を GET のハンドラへ流す。HEAD /download・HEAD /dl/:tag/:file・HEAD /releases/:tag/:file のいずれも download を 1 件記録し、HEAD / は visit を 1 件記録していた。本文を 1 バイトも受け取らない要求が配信・閲覧として数えられていたのが、過大計上の実体。

修正は経路側ではなく recordEvent（site/src/events.ts）に置いた。3 経路に個別に置くと、ダウンロード経路を足すたびに同じ穴が空くため（指摘の 1 箇所ではなく絞り込み点で直す）。kind を問わず落としているのは、閲覧も配信も『本文を受け取ったこと』を数えているためで、HEAD にはそれが無い。

判断の記録:
- 302 フォールバックは計上を続ける。R2 に実体が無い旧タグは GitHub へ 302 するが、これは失敗ではなく別ホストへの引き渡しであり、利用者は実際に取得する。除外すると過小計上になる。起票時の『配信に成功した要求だけ』はこの解釈で満たす（弾くのは HEAD、すなわち配信が始まらない要求）。
- レンジ要求の再接続は該当しなかった。dmgResponse は Range を解釈せず常に 200 で全体を返す（site/src/routes/public.tsx:180-198）ため、部分取得の重複計上は起きない。再接続は全体の取り直しであり、1 件として数えるのが妥当。
- lp / sparkle / archive の計上条件は元から揃っていた。3 経路とも R2 の取得判定より前で記録し、302 も計上する。差は無かったので揃える変更は不要。HEAD 除外も recordEvent の 1 箇所なので 3 経路に同時に効く。
- 既存データは遡って直さない。HEAD 由来の行かどうかを判別できる列が events に無く（method を記録していない）、推定で消すと本物のダウンロードまで落ちる。今後の記録だけが正しくなる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
HEAD 要求を計測から外した。Hono が HEAD を GET ハンドラへ流すため、本文を受け取らない要求が全 3 経路で download として、LP では visit として記録されていた（使い捨てテストで実測）。修正は記録の絞り込み点である recordEvent に置き、経路を足しても同じ穴が空かないようにした。302 フォールバックは引き渡しの成功として計上を続ける判断とし、レンジ再接続は Range 非対応のため該当しないことを確認した。検証: 3 経路 + LP の HEAD と GET を並べたテストを追加し、修正前に 4 件失敗することを確認。site の vitest 369 件すべて green。
<!-- SECTION:FINAL_SUMMARY:END -->
