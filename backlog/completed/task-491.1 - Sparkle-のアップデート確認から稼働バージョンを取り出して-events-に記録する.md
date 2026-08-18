---
id: TASK-491.1
title: Sparkle のアップデート確認から稼働バージョンを取り出して events に記録する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-16 02:35'
updated_date: '2026-08-16 06:52'
labels: []
milestone: m-7
dependencies: []
parent_task_id: TASK-491
priority: medium
ordinal: 728000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-491 の記録側。ダッシュボードの表示は TASK-491.2 で扱う。

`update_check` に「そのリクエストを出したアプリが今どのバージョンか」を持たせる。現状は `recordEvent(c, { kind: 'update_check', channel })` だけで version を渡しておらず（`site/src/routes/public.tsx:146`）、本番 D1 の `update_check` 132 件は全件 `version` NULL / `os` NULL（2026-08-16 実測）。

## 最初にやること: 生 UA の実測

`summarizeUA` は Sparkle の UA を `'Sparkle'` の 1 語へ丸めるため（`site/src/lib/visitor.ts:137`）、実際に何が届いているかは D1 からは分からない。Sparkle の既定 UA は `<CFBundleName>/<version> Sparkle/<x.y>` 形式とされるが、befold で実際にどう出るかは未確認。**Worker のログ（`wrangler tail` / Workers Observability）で生 UA を 1 度だけ確認し、パースできる形かを確定させてから実装する。** アプリを develop チャネルで起動すればアップデート確認が飛ぶ。

## 決めること（親タスクから引き継ぎ）

- UA からアプリバージョンを取る（アプリ側の変更なし・追加送信なし）。OS バージョンまで欲しい場合は `SUEnableSystemProfiling` の有効化が必要になり、送信する端末情報が増えるため**このサブタスクでは実施せず**、必要と判断したら ADR を起こして別タスクにする。判断結果を Implementation Notes に残すこと。
- `version` 列を流用するか新しい列を足すか。現状 `version` は `download` では「ダウンロード対象のタグ」の意味であり、`update_check` に稼働中バージョンを入れると 1 列に 2 つの意味が同居する。既存の `byVersion` 集計（`site/src/analytics.ts`）の意味が変わらないことを確認した上で決め、選んだ理由を Implementation Notes に残す。

## 注意

- UA は生値を保存しない方針（`site/src/events.ts` は `summarizeUA` / `summarizeOS` の結果だけを入れる）。バージョンも同様に、抽出した値だけを入れて生 UA は残さない。
- 抽出は失敗しうる（curl からの `update_check` が実測で 31 件ある）。パースできないときは NULL にして記録処理自体は止めない。
- ボット判定は既存の `ua_summary` の `bot:` 接頭辞をそのまま使い、新しい判定を作らない（`site/src/lib/visitor.ts:104-131`、集約点は `site/src/analytics.ts` の `HUMAN_ONLY`）。
- スキーマ変更は Atlas 運用（`site/schema/schema.sql` → `npm run migrate:diff` → `migrate:lint` → `migrate:local`。`site/README.md:59-73`）。`ADD COLUMN` で足す。
- 実装着手前に `/review-design` を 1 回回す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Sparkle が実際に送る User-Agent の実測結果が Implementation Notes に記録されている
- [x] #2 update_check に稼働中のアプリバージョンが記録され、download の version（対象タグ）と意味が区別できる
- [x] #3 パースできない User-Agent では NULL になり、記録処理が失敗しない
- [x] #4 version 列を流用したか新設したか、その理由が Implementation Notes に記録されている
- [x] #5 マイグレーションが Atlas 運用で生成され、テーブル再構築を含まない
- [x] #6 抽出処理のユニットテストがあり、Sparkle / curl / 空の UA を含む
- [x] #7 site の vitest と typecheck が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. /review-design を実施済み（結果は Implementation Notes）。決定: version 列は流用せず app_version を新設、値は UA が報告する形（v 接頭辞なし）、SUEnableSystemProfiling は有効化しない。
2. site/src/lib/visitor.ts に summarizeAppVersion(ua) を追加。'befold/<ver> Sparkle/' に前方一致したときだけ版を返す。アプリ名は befold 固定、版はバージョン様の形＋長さ上限で縛る（UA は詐称可能でカーディナリティが発散するため）。それ以外は null。
3. site/schema/schema.sql に app_version 列を追加し、NULL の 3 通りの意味（列導入前 / 非 Sparkle クライアント / パース失敗）をコメントに書く。npm run migrate:diff -- add_app_version → migrate:lint → migrate:local。
4. site/src/schema.ts の eventSchema に appVersion を追加（nullable default null）。refine は足さない（kind に依らず UA から導出するため）。
5. site/src/events.ts の INSERT_SQL / insertEvent / bind に app_version を追加。EventAttributes には足さない——host と同じく呼び出し側から渡せない構造にして付け忘れを起こりえなくする。
6. テスト: test/visitor.test.ts に summarizeAppVersion の実測 UA（befold/1.13.2-dev.4 Sparkle/2.9.4）・curl・空文字・詐称 UA を追加。test/public.test.ts に appcast 経由で app_version が記録されることの検証を追加。
7. npm run test / typecheck を通す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Sparkle の生 UA（実測、2026-08-16）

```
befold/1.13.2-dev.4 Sparkle/2.9.4
```

取り方: Sparkle の UA は `SPUUpdater.userAgentString` が **main bundle** から組み立てる（hostBundle ではない）。そこで `/Applications/befold.app/Contents/Info.plist` をそのまま Info.plist に持つ probe.app を作り、その中の実行ファイルから `SPUUpdater.userAgentString` を出力した。Sparkle 側の書式文字列も `strings` で `%@%@/%@ Sparkle/%@` を確認（先頭の `%@` は実測で空）。Sparkle のバージョンは 2.9.4（`Sparkle.framework/Resources/Info.plist`）。

`wrangler tail` は使っていない。Worker は UA をログに出しておらず、生 UA を取るにはログ出力の追加（＝生 UA を一時的にでも外へ出す）が要るため、クライアント側で直接測るほうが安全で再現性も高いと判断した。

## 決めたこと

**version 列は流用せず `app_version` を新設した。** `version` は download が「どのタグを取りに来たか」で、値もタグそのもの（`v1.13.2-dev.4`）。稼働版は `v` の付かない `1.13.2-dev.4` で、同じ列に入れると `site/src/analytics.ts` の `byVersion`（`kind=download AND COALESCE(source,lp)=lp`、`analytics.ts:459-467,89-93`）が 2 つの意味を混ぜて数えることになる。列を分けたので byVersion の SQL も値も変わっていない。

**値は UA が報告する形のまま（`v` 接頭辞なし）で保存する。** タグとの比較が要るのは表示側（TASK-491.2）だけなので、正規化はそこ 1 箇所でやる。

**`SUEnableSystemProfiling` は有効化しない。** OS バージョンは今回見送り。有効にすると `appVersion` / `osVersion` / `model` / `ncpu` / `ramMB` / `lang` が appcast URL に付き、送信する端末情報が増える。必要と判断したら ADR を起こして別タスクにする。

**呼び出し側から渡せない構造にした。** `EventAttributes` に `appVersion` を足さず、`insertEvent` が UA から一括導出する（`host` と同じ持ち方）。Sparkle が通る経路は update_check だけでなく download(source='sparkle') / github_fallback(appcast) もあるため、呼び出し側に渡させると経路を足すたびに付け忘れが起き、その経路だけ稼働版が欠測する。doc コメントではなく構造で担保している。

**UA の素通しはしない。** UA は詐称できるヘッダなので、アプリ名を `befold` に固定し、版もバージョン様の形＋長さ上限に縛った（`APP_VERSION_PATTERN`）。素通しにすると `app_version` の内訳が任意文字列で発散する。プレリリース識別子は形だけを縛って値は列挙していない（`-beta.1` などが将来来ても落ちないようにするため）。

## /review-design の結果

該当したのは項目 1（判定の真実の源）・3（消費経路の全列挙）・7（測るものと守るものの一致）・9（決めた粒度を守らせるもの）。対処は上記のとおり実装へ反映済み。項目 2 は byVersion が `kind='download'` に限定されているため衝突なし、項目 5・6・8 は非該当（導出は挿入時 1 回、正規表現 1 回、非同期の表示状態なし）、項目 10 は Swift 専用のため対象外。項目 4（新しい状態の表示）は TASK-491.2 の担当で、NULL の 3 通りの意味を `schema/schema.sql` のコメントへ残した。

## 検証

- `npm test` → 12 files / 264 tests すべて通過
- `npm run typecheck` → エラーなし
- `npm run migrate:lint` → `no diagnostics found`（生成物は `ALTER TABLE ... ADD COLUMN` 1 文のみで、テーブル再構築を含まない）
- `npm run migrate:local` → 適用済み
- **修正を戻して落ちることを確認**: `appVersion: summarizeAppVersion(ua)` を `appVersion: null` に差し替えると `稼働中のアプリバージョンを app_version に記録する（TASK-491.1）` が 1 件 fail する（差し替え後に復元済み）

## 補足

events テーブルの現在仕様は `site/schema/schema.sql` のコメントが単一の情報源で、`docs/dev/` 側に対応する節は無い（`docs/dev/development.md:152` が update_check に触れるのみ）。そのため現在仕様の更新は schema.sql のコメント追記で完了している。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Sparkle の生 UA を実測（`befold/1.13.2-dev.4 Sparkle/2.9.4`）し、そこから稼働中バージョンだけを抽出して events の新設列 `app_version` に記録するようにした。抽出は `summarizeAppVersion`（`site/src/lib/visitor.ts`）に集約し、アプリ名を befold に固定・版の形を縛って詐称 UA を素通ししない。導出は `insertEvent` が UA から一括で行い、`EventAttributes` には足さないので呼び出し側の付け忘れが起こりえない（`host` と同じ持ち方）。`version`（download の対象タグ）とは列を分けたため `byVersion` 集計は不変。マイグレーションは Atlas 生成の ADD COLUMN 1 文で lint も通る。検証は `npm test`（264 tests 通過）・`npm run typecheck`・`migrate:lint` と、実装を戻すと該当テストが落ちることの確認。
<!-- SECTION:FINAL_SUMMARY:END -->
