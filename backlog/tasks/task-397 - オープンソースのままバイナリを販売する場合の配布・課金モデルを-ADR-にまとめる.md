---
id: TASK-397
title: オープンソースのままバイナリを販売する場合の配布・課金モデルを ADR にまとめる
status: To Do
assignee: []
created_date: '2026-08-09 13:34'
labels: []
dependencies: []
priority: low
type: task
ordinal: 505000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
将来の選択肢として、ソースは公開したままバイナリを有償にするモデルを検討している。配布経路は既に GitHub Releases から独自サイト（Cloudflare Worker + R2）へ移してあり、ダウンロードと自動更新の両方が Worker を経由する構成になっている。この位置に課金の判定を置ける状態にはあるが、どのモデルを採るかは未決。

このタスクは調査と意思決定の記録のみで、実装は伴わない。今すぐ有償化する判断ではなく、選択肢と前提を ADR として残し、必要になったときに再検討から始めなくてよい状態にすることが目的。

検討対象の選択肢:
1. アプリ内ライセンス方式 — バイナリは誰でも取得できる。起動時にライセンスキーを検証し、無ければ試用期間 / 機能制限 / 起動時のナグ。摩擦が最小。
2. 更新のみ有料 — 初回ダウンロードは自由、/dl と appcast にライセンストークンを要求する。現構成にほぼそのまま乗る。
3. ライセンス変更 — MIT から source-available 系（BSL / FSL 等）へ変更する。これは『オープンソースのまま』ではなくなるため、上の 2 つとは性質の違う判断。

前提と裏付け:
- コード参照: 現行ライセンスは LICENSE（MIT）。MIT はコンパイル済みバイナリの再配布も許可するため、ダウンロードゲートは法的な保護にならない。
- コード参照: 配布経路は site/src/routes/public.tsx の /download（LP 経由、source='lp'）と /dl/:tag/:file（Sparkle 経由、source='sparkle'）。成果物の所在解決は site/src/lib/dist.ts。
- コード参照: 現在の D1 は events テーブル 1 枚のみ（site/schema/schema.sql）。ライセンス管理には licenses / activations 相当の追加が要る。
- 実測（2026-08-09、本番 D1）: 2026-07-29 以降で visit 216 件（ボット込み）、download 11 件。普及段階として有償化の判断材料になる規模には達していない。
- 未確認: 決済基盤の選定（Lemon Squeezy / Paddle 等の Merchant of Record を使うと各国の消費税・VAT を自前で処理せずに済む）。手数料と日本の個人事業主としての扱いは調べていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 3 つの選択肢それぞれについて、守れるもの・守れないもの・必要な実装が整理されている
- [ ] #2 MIT のままではダウンロードゲートが保護として機能しないことが、根拠とともに記録されている
- [ ] #3 現時点では採用しない（判断を保留する）という結論と、再検討の条件（どの指標がどうなったら着手するか）が明記されている
- [ ] #4 ADR が docs/adr/ 配下に既存の採番規則に従って追加されている
<!-- AC:END -->
