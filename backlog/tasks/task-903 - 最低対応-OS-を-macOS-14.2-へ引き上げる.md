---
id: TASK-903
title: 最低対応 OS を macOS 14.2 へ引き上げる
status: Done
assignee: []
created_date: '2026-10-30T10:27:00Z'
updated_date: '2026-10-30T10:48:00Z'
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
- [x] #1 Custom Highlight API が macOS 14.2 の WebKit で使えることを一次情報（WebKit / Safari のリリースノート）で確認し、出典を Notes に残す
- [x] #2 アプリ・QuickLook 拡張・CLI を含む全ターゲットの最低対応が 14.2 になり、14.1 以前ではインストール・起動できない（Info.plist の `LSMinimumSystemVersion` が 14.2 になっていることをビルド成果物で確認）
- [x] #3 Sparkle で 14.1 以前の環境へ新版が配信されない、または配信されても問題にならないことを確認し、結論を Notes に残す
- [x] #4 README（英日）と配布サイトの動作要件の表記が 14.2 に揃い、サイトのテストが通る
- [x] #5 `docs/dev/` の現在仕様にある最低対応 OS の記述が 14.2 に揃う
- [x] #6 次の stable で `/changelog` が利用者向けに拾えるよう、この変更を `feat!:`（BREAKING CHANGE 付き）のコミットとして入れ、PR のタイトルも同じ扱いにする旨を Notes に残す
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
一次情報: WebKit 公式ブログ「WebKit Features in Safari 17.2」（https://webkit.org/blog/14787/webkit-features-in-safari-17-2/）に "Safari 17.2 adds support for the Custom Highlights API." とある。Sonoma では Safari 17.2 が macOS 14.2（2023-12-11）に同梱（https://eclecticlight.co/2023/12/11/what-has-changed-in-macos-sonoma-14-2/ の変更一覧に Safari 17.2）。WKWebView はシステムの WebKit を使うため、14.2 以上なら常に API がある。

ビルド成果物（xcodebuild -derivedDataPath .build/xcode, Debug）: 本体・BefoldQuickLook.appex・BefoldKit / BefoldPDFProbe / BefoldRenderKit framework の Info.plist の LSMinimumSystemVersion がすべて 14.2。befold / befold-cli の Mach-O の minos も 14.2（vtool -show-build）。SPM 側は `.macOS("14.2")`（swift package describe で Version: 14.2）。

Sparkle: 配信中の appcast（releases/download/appcast/appcast.xml）の各 item に <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion> が入っている。generate_appcast が Info.plist の LSMinimumSystemVersion から書き出しているため、引き上げ後の版の item は 14.2 になり、14.1 以前の Sparkle はその版を候補から外す（既存の版は 14.0 のまま残り、そこで止まる）。

CHANGELOG: CHANGELOG.md は /release 時に /changelog が書く運用で未リリース節が無く、chore: は載らない（.claude/skills/changelog/SKILL.md）。そのため AC #6 を「feat! で入れる」に書き換えた。squash マージの PR タイトルは feat!: で始めること。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
最低対応 OS を macOS 14.0 から 14.2 へ引き上げた（project.yml の deploymentTarget、Package.swift の platforms）。README（英日）、配布サイトの動作要件と JSON-LD とそのテスト、docs/dev、.claude/CLAUDE.md、サンプルの表記を 14.2 に揃えた。目的は TASK-902 で検索ハイライトを CSS Custom Highlight API に一本化し、<mark> 経路を削除できるようにすること。検証: ビルド成果物の全ターゲットで LSMinimumSystemVersion / minos が 14.2、site の public-routes テスト 52 件成功、markdownlint 0 件。Sparkle は generate_appcast が minimumSystemVersion を書き出すので、14.1 以前へは新版が配信されない。
<!-- SECTION:FINAL_SUMMARY:END -->
