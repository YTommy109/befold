---
id: TASK-491.1
title: Sparkle のアップデート確認から稼働バージョンを取り出して events に記録する
status: To Do
assignee: []
created_date: '2026-08-16 02:35'
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
- [ ] #1 Sparkle が実際に送る User-Agent の実測結果が Implementation Notes に記録されている
- [ ] #2 update_check に稼働中のアプリバージョンが記録され、download の version（対象タグ）と意味が区別できる
- [ ] #3 パースできない User-Agent では NULL になり、記録処理が失敗しない
- [ ] #4 version 列を流用したか新設したか、その理由が Implementation Notes に記録されている
- [ ] #5 マイグレーションが Atlas 運用で生成され、テーブル再構築を含まない
- [ ] #6 抽出処理のユニットテストがあり、Sparkle / curl / 空の UA を含む
- [ ] #7 site の vitest と typecheck が通る
<!-- AC:END -->
