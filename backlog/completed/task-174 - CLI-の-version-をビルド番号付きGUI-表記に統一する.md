---
id: TASK-174
title: CLI の --version をビルド番号付き(GUI 表記)に統一する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 00:43'
updated_date: '2026-07-28 01:49'
labels:
  - cli
  - version
dependencies: []
priority: medium
type: bug
ordinal: 249000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GUI と CLI でバージョン表記が異なる。GUI は "1.9.1-dev.5 (801)" のようにビルド番号(CFBundleVersion)を括弧付きで表示するが、CLI(befold --version)は "1.9.1-dev.5" とビルド番号を含まない。AppVersion.current が CFBundleShortVersionString のみを返しているため。GUI 表記に合わせ、CLI も "<ShortVersion> (<BundleVersion>)" 形式で表示できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold --version が GUI と同じ "<ShortVersion> (<BundleVersion>)" 形式で表示される
- [x] #2 CFBundleVersion が取得できない(バンドル外/SPM 単体ビルド等)場合の表示フォールバックが定義され、クラッシュや空括弧にならない
- [x] #3 GUI 側のバージョン表記との一貫性が担保される(共通のフォーマット箇所を用いる等)
- [x] #4 AppVersion まわりのテストがビルド番号付き表記を検証する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit(最下層)に共通フォーマッタ VersionFormatting.versionString(short:build:) を新設。build が nil/空/$(...)プレースホルダなら括弧を付けず short のみ(空括弧・クラッシュ回避=AC#2)。
2. AppVersion(BefoldCLI)に import BefoldKit し resolvedWithBuild(infoDictionary:) / currentWithBuild を追加。既存 current(short のみ)は温存。
3. CLI の CommandConfiguration version を AppVersion.current → AppVersion.currentWithBuild に変更(AC#1)。
4. QuickLookBadge.text を VersionFormatting 経由に寄せて (build) フォーマットの重複を解消(共通のフォーマット箇所=AC#3)。既存テスト文字列は不変を維持。
5. AppVersionTests に resolvedWithBuild のケース追加(short+build/build欠落/空/プレースホルダ/nil)=AC#4。VersionFormatting 単体テストも追加。
6. GUI About は AppKit が同じ2キーから同体裁を生成するため一貫性を担保(AC#3)。swift test 全緑を確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: swift test 全 810 テスト緑(新規 AppVersion 5件 + VersionFormatting 4件)。AppVersionTests.resolvedWithBuildFormatsShortAndBuild が {CFBundleShortVersionString:9.9.9-dev.1, CFBundleVersion:801} → "9.9.9-dev.1 (801)" を検証(AC#1 の形式)。フォールバック各種(build 欠落/空/$()/infoDict nil)で空括弧にならず short のみを検証(AC#2)。SPM 単体ビルドの befold-cli --version 実行は "1.9.0"(バンドル外フォールバック、クラッシュ・空括弧なし)を実測。
実装: BefoldKit に共通フォーマッタ VersionFormatting.versionString(short:build:) を新設(build が nil/空/$()なら括弧を付けず short のみ)。AppVersion(BefoldCLI)に resolvedWithBuild/currentWithBuild を追加し CLI の CommandConfiguration version を currentWithBuild に変更。QuickLookBadge も同フォーマッタ経由に寄せ (build) 整形の重複を解消(AC#3)。GUI About は AppKit が同 2 キーから同体裁を生成するため一貫。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI の --version を GUI と同じ "<ShortVersion> (<BundleVersion>)" 形式に統一。BefoldKit に共通フォーマッタ VersionFormatting を新設して CLI(AppVersion.currentWithBuild)と QuickLook バッジを同一経路に寄せ、GUI About(AppKit 自動整形)と体裁を揃えた。ビルド番号が取れない場合は空括弧にせず short のみへフォールバック。swift test 810 件緑、CLI 実バイナリ実行と単体テストで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
