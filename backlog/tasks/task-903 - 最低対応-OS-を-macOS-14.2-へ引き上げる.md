---
id: TASK-903
title: 最低対応 OS を macOS 14.2 へ引き上げる
status: To Do
assignee: []
created_date: '2026-10-30T10:27:00Z'
labels: []
dependencies: []
priority: low
ordinal: 863000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
検索ハイライトを CSS Custom Highlight API（`Highlight` / `StaticRange` / `::highlight`）に一本化し、古い WebKit 向けの `<mark>` 挿入経路を削除したい（TASK-902）。現在の最低対応は macOS 14.0 で、この API は Safari 17.2 相当の WebKit（macOS 14.2）から使える（未確認の認識。着手時に裏付けを取る）。14.0〜14.1 を残す限りフォールバックを消せない。

利用者は 10 人前後の見込みで、14.x のマイナーアップデートは通常配信されるため、14.0〜14.1 に留まる利用者はほぼいないと判断して 14.2 にする（2026-10-30 ユーザー判断）。なお配布サイトのダッシュボードにある OS 内訳は根拠にならない: ブラウザは UA を `Mac OS X 10_15_7` に固定するため常に「macOS 10.15」と記録され、Sparkle の UA（`befold/x Sparkle/y`）は OS を含まない（`site/src/lib/visitor.ts` の `summarizeOS`）。

現時点で 14 を宣言している箇所: `BefoldApp/project.yml` の `deploymentTarget`、`BefoldApp/Package.swift` の `platforms`、`README.md` / `README.ja.md`（バッジと動作要件）、`site/src/views/shared.tsx` の動作要件文言と `site/src/views/landing.tsx` のコメント、それを検査する `site/test/public-routes.test.ts`、`sample/presentation/25-thanks.html`。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Custom Highlight API が macOS 14.2 の WebKit で使えることを一次情報（WebKit / Safari のリリースノート）で確認し、出典を Notes に残す
- [ ] #2 アプリ・QuickLook 拡張・CLI を含む全ターゲットの最低対応が 14.2 になり、14.1 以前ではインストール・起動できない（Info.plist の `LSMinimumSystemVersion` が 14.2 になっていることをビルド成果物で確認）
- [ ] #3 Sparkle で 14.1 以前の環境へ新版が配信されない、または配信されても問題にならないことを確認し、結論を Notes に残す
- [ ] #4 README（英日）と配布サイトの動作要件の表記が 14.2 に揃い、サイトのテストが通る
- [ ] #5 `docs/dev/` の現在仕様にある最低対応 OS の記述が 14.2 に揃う
- [ ] #6 CHANGELOG（次の stable のリリースノート）に最低対応 OS の変更を利用者向けに記載する
<!-- AC:END -->
