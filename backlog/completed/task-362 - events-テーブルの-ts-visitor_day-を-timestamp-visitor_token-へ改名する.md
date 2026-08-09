---
id: TASK-362
title: events テーブルの ts / visitor_day を timestamp / visitor_token へ改名する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 07:16'
updated_date: '2026-08-08 07:19'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 623000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
events テーブルの列名が実体と合っておらず誤読を招く。visitor_day は名前から日付列に見えるが、実体は sha256(IP + UA + JST日付) の 64 桁ハッシュで『その日限りの訪問者トークン』である（site/src/lib/visitor.ts:13）。ts も省略形で、日時列であることが名前から伝わらない。実際にレビューで『日時カラムがない設計に見える』という誤読が起きた。

あわせて、TASK-359.2 で入れた visitor_day の JST 化に伴う不連続の注記を削除する。訪問者数がまだ少なく、不連続を無視して差し支えないというユーザー判断による。

## 制約

- カラム改名は ALTER TABLE ... RENAME COLUMN を含むため scripts/check-destructive-migrations.sh に捕捉され、CI の自動デプロイが失敗する。本番・staging へは手動で migrate してから deploy する必要がある（site/README.md『破壊的なマイグレーションは自動適用されない』）
- マイグレーションはデプロイより先に当てる。順序が逆だと新コードの INSERT がカラム不足で失敗し、insertEvent は例外を飲む設計のため計測が無言で欠落する（site/README.md）
- atlas は未インストールのためマイグレーションは手書きし、migrations/atlas.sum も手で再生成する。checksum の式は実測で特定済み: 各ファイルのハッシュは name+content を順に流し込む単一の走行ハッシュのスナップショット、総和行は各行の name + hash(h1: 接頭辞なし) の連結の sha256
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 events の ts が timestamp に、visitor_day が visitor_token に改名されている
- [x] #2 schema/schema.sql（desired state）と migrations/ の内容が一致し、atlas.sum が正しく再生成されている
- [x] #3 アプリ側（analytics.ts / events.ts / schema.ts / lib/jst.ts / views/dashboard.tsx）と全テストが新しい列名を使っている
- [x] #4 visitor_day の JST 化に伴う不連続の注記がダッシュボードから削除されている
- [x] #5 ローカル D1 にマイグレーションを適用したうえでダッシュボードが 200 で描画される
- [x] #6 既存データが失われないこと（RENAME COLUMN であり再作成でないこと）がマイグレーションの内容から確認できる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-08 実装完了。

改名:
- events.ts → events.timestamp、events.visitor_day → events.visitor_token
- インデックス idx_events_ts → idx_events_timestamp（SQLite は RENAME COLUMN でインデックス定義の参照を自動追従するが名前は古いままになるため貼り直した）
- 関数名も実体に合わせて visitorDayHash → visitorTokenHash
- zod のフィールドも ts → timestamp、visitorDay → visitorToken

マイグレーション（migrations/20260808071500_rename_ts_and_visitor_day.sql）:
- ALTER TABLE ... RENAME COLUMN を使用。テーブル再作成ではないため既存データは保持される
- atlas が未インストールのため手書きし、atlas.sum も手で再生成した。checksum の式は既存 3 エントリすべてを再現できることを確認してから適用している:
  - 各ファイルのハッシュ = base64(sha256) の、name+content を順に流し込む単一の走行ハッシュのスナップショット
  - 総和行 = base64(sha256(各行の name + hash（h1: 接頭辞なし）の連結))
  - 再生成後も既存 3 エントリのハッシュは変化しなかった（並び順が保たれている証拠）

注記の削除:
- TASK-359.2 で入れた visitor_day の JST 化に伴う不連続の注記と、その CSS（.notice）を削除した。ユーザー判断（訪問者数が少なく無視してよい）による
- JST 基準である旨の明示はヘッダーに残し、『SSE の差し替え範囲の外に置く』テストもそちらへ付け替えた

検証（実測）:
- npx vitest run: 74 passed / 6 files、npx tsc --noEmit エラーなし
- ローカル D1 へ適用: 適用前 344 行 → 適用後 344 行（COUNT / MIN(timestamp) / COUNT(DISTINCT visitor_token)=122 を確認）。データ欠損なし
- インデックス一覧が idx_events_kind / idx_events_timestamp になっていることを sqlite_master で確認
- wrangler dev を再起動し、ダッシュボードが 200・グラフ 7 個 / 棒 128 本・NaN なし・注記なしで描画されることを確認
- 書き込み経路も確認: / へアクセスして 344 → 345 行に増えることを確認（新しい列名で INSERT できている）

未対応（報告済み）: docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md:92-101 に旧列名のスキーマ記載が残る。日付つきの設計文書のため履歴として残す判断。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
events.ts を timestamp へ、events.visitor_day を visitor_token へ改名した。visitor_day は名前から日付列に見えるが実体は『その日限りの訪問者トークン』（64 桁ハッシュ）で、実際に誤読を生んでいたため。ALTER TABLE RENAME COLUMN を使いデータは保持される（ローカル D1 で 344 行が前後で不変であることを実測）。atlas 未インストールのため atlas.sum は手で再生成し、既存 3 エントリを再現できる式であることを検証してから適用した。あわせて JST 化の不連続の注記をユーザー判断により削除。vitest 74 件 pass、tsc エラーなし、ローカルで読み書き両経路の動作を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
