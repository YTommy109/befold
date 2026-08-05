---
id: TASK-237
title: バージョン文字列取得を共通化し About 画面の表示不備を修正する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:16'
updated_date: '2026-07-31 15:38'
labels:
  - refactor
dependencies: []
priority: low
type: task
ordinal: 440000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Info.plist からのバージョン読み取りが 3 実装ある: AboutView.swift:43-48（取れないと空文字表示になる不整合あり）/ BefoldKit/AppLinks.swift:34-40 / BefoldCLI/AppVersion.swift:34-51（$( プレースホルダ判定つき）。CFBundleShortVersionString 等のキーリテラルと hasPrefix("$(") 判定が散在している。BefoldKit/VersionFormatting に infoDictionary → 整形済み文字列（取れなければ nil）の共通実装を置き、フォールバックの決定は呼び出し側に残す。副産物として About パネルが空文字になる現在の不整合を是正する。併せて AboutView.swift:9 の body 内 NSImage(contentsOfFile:) 評価（body ごとにディスク読み直し）を init/State への退避で解消する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 バージョン文字列の取得・整形が 1 実装に集約され、3 箇所の表示が従来の意図どおり（About は空文字にならない）
- [x] #2 AboutView の画像読み込みが body 評価ごとに走らない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. VersionFormatting に Info.plist 読み取り(shortVersion / buildNumber / versionString(infoDictionary:))を追加し、キーリテラルと $( プレースホルダ判定を集約
2. AppVersion / QuickLookBadge / AboutView をその共通実装へ寄せる
3. AboutView は AppVersion.resolvedWithBuild を使い、Info.plist 不在時も空文字にならないようにする
4. AboutView の OGP 画像読み込みを body から init へ退避
5. VersionFormatting のテストを追加
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CFBundleShortVersionString / CFBundleVersion のキーリテラルと未置換プレースホルダ判定を VersionFormatting へ集約し、AppVersion・QuickLookBadge・AboutView の 3 実装がすべてそこを経由するようにした。About は独自の Info.plist 読み取り(短縮バージョンが取れないと空文字表示)をやめ、CLI --version と同じ AppVersion.resolvedWithBuild を使う形に変更（AppVersion.fallback があるため空文字にならない。既存の AppVersionTests がフォールバック挙動を担保）。副次的に QuickLookBadge も短縮バージョンが未置換プレースホルダのとき『befold QL』へ落ちるようになった（従来は '$(MARKETING_VERSION)' をそのまま表示していた）。AboutView は OGP 画像読み込みとバージョン算出を init へ退避し、body 評価ごとのディスク読み直しを解消。検証: swift test --skip Integration --skip FileWatcherTests → 937 tests passed（VersionFormattingTests に Info.plist 経路のテストを 3 件追加）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Info.plist からのバージョン取得を VersionFormatting に一本化し、AppVersion / QuickLookBadge / AboutView の 3 実装を集約。About パネルが空文字になりうる不整合を AppVersion 経由にして解消し、AboutView の body 内画像読み込みも init へ退避した。swift test 937 件パスで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
