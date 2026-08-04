---
id: TASK-72.4
title: QuickLook Extension のターゲット・Info.plist・entitlements を設定する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-19 06:44'
updated_date: '2026-07-26 05:45'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 214000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
project.yml に app-extension タイプの QuickLook Extension ターゲットを追加し、befold アプリターゲットへの embed 依存を設定する。Info.plist に QLSupportedContentTypes(対象UTI一覧)と NSExtension 辞書を設定し、entitlements にサンドボックス有効・ネットワークなしを設定する。.svg は public.xml 側に紐づけ、画像系UTIとの重複を避ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 xcodegen generate で QuickLook Extension ターゲットが生成される
- [x] #2 Info.plist の QLSupportedContentTypes が対象拡張子のUTIのみを含み、PDF/画像のUTIを含まない
- [x] #3 entitlements でサンドボックスが有効になっており、不要な権限(ネットワーク等)が付与されていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 単純化検討
QLSupportedContentTypes を独自に列挙せず、アプリ本体 Info.plist の
CFBundleDocumentTypes(LSItemContentTypes)の和集合を単一情報源として写す。
befold が「どの UTI を扱うか」は既にそこで決着済み(.mmd を net.ia.markdown が
奪う件、.md の com.unknown.md 等の実環境の衝突も織り込み済み)であり、
QuickLook 側で別リストを持つと二重管理になる。差分は SVG のみ。

## SVG の扱い(当初計画からの変更)
当初計画は「.svg を public.xml 側に紐づけて画像 UTI との重複を避ける」だったが、
実機の UTType(filenameExtension:"svg") は public.svg-image に解決され、
public.xml には解決されない(TASK-72.1 で採取)。親タスク AC#1 の
「.svg をレンダリングモードでプレビューできる」を満たすには public.svg-image の
宣言が必要なため、ユーザー確認のうえ public.svg-image を宣言する方針に変更した。

## 手順
1. QLSupportedContentTypes がアプリ本体の CFBundleDocumentTypes と一致し、
   PDF/画像 UTI を含まないことを検証するテストを追加する(失敗を確認)
2. BefoldQuickLook/Info.plist の QLSupportedContentTypes を確定する
3. entitlements にサンドボックス有効・ネットワーク権限なしを確認する
4. xcodegen generate / xcodebuild / swift test で確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装
- ターゲット BefoldQuickLook(type: app-extension)は TASK-72.1 の実機検証時に
  追加済み。本タスクでは QLSupportedContentTypes の確定と検証テストを行った。
- QLSupportedContentTypes はアプリ本体 Info.plist の CFBundleDocumentTypes
  (LSItemContentTypes)の和集合をそのまま写し、public.svg-image のみ追加した。
  独自リストを持たないことで、実環境の UTI 衝突に関する既存の決着
  (.mmd → net.ia.markdown、.md → com.unknown.md 等)をそのまま引き継ぐ。
- SVG は当初計画の「public.xml 側に紐づける」を採らず public.svg-image を宣言。
  実機の UTType(filenameExtension: "svg") が public.svg-image に解決され
  public.xml には解決されないため(ユーザー確認済み)。

## 検証
- AC#1: xcodegen generate → xcodebuild -list の Targets に BefoldQuickLook が出る。
  xcodebuild build -scheme befold → BUILD SUCCEEDED、警告なし。
- AC#2: 新規 QuickLookInfoPlistTests で
  - QLSupportedContentTypes == アプリ本体 CFBundleDocumentTypes ∪ {public.svg-image}
  - com.adobe.pdf / public.pdf / public.png / public.jpeg / com.compuserve.gif /
    org.webmproject.webp / com.microsoft.bmp / com.microsoft.ico / public.image を含まない(9ケース)
- AC#3: entitlements のテストに加え、ビルド成果物の実効 entitlements を
  codesign -d --entitlements で確認:
    com.apple.security.app-sandbox = true
    com.apple.security.files.user-selected.read-only = true
    (network.client / network.server は無し。get-task-allow は Debug ビルド固有)
- swift test → 706 tests / 101 suites パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldQuickLook(app-extension)の QLSupportedContentTypes を確定した。独自 UTI リストを持たず、アプリ本体 CFBundleDocumentTypes の和集合 + public.svg-image という導出にして二重管理を避けた。SVG は実機の UTI 解決が public.svg-image であるため当初計画の public.xml から変更(ユーザー確認済み)。QuickLookInfoPlistTests で対象 UTI と entitlements のドリフトを検知し、xcodebuild のビルド成功と codesign -d による実効 entitlements(サンドボックス有効・ネットワーク権限なし)を確認。swift test 706 件パス。
<!-- SECTION:FINAL_SUMMARY:END -->
