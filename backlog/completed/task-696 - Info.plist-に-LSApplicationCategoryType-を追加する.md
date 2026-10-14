---
id: TASK-696
title: Info.plist に LSApplicationCategoryType を追加する
status: Done
assignee: []
created_date: '2026-10-09 13:29'
updated_date: '2026-10-12 11:54'
labels:
  - tech-debt
dependencies: []
priority: low
ordinal: 885000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/Info.plist` に `LSApplicationCategoryType` が無い(App Store 掲載調査 2026-10-09 で確認。project.yml 側にも無い)。Finder の「カテゴリ」表示などに使われ、将来 Mac App Store に出す場合は必須になる。1 行で済む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `LSApplicationCategoryType` が本体の Info.plist(生成後の値)に入っている。カテゴリは Developer Tools か Productivity のうち、配布サイトの説明に合う方を選び、理由を Notes に残す
- [x] #2 Info.plist を検査する既存テストがあれば通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
LSApplicationCategoryType は Developer Tools(public.app-category.developer-tools)にした。配布サイトの説明(site/src/views/features.tsx、landing.tsx)は Mermaid・Markdown・ソースコード・CSV/TSV などを読む編集機能のない閲覧専用ファイルビューアで、文書を作る・管理する Productivity より、開発者がエディタの隣で成果物を確認する用途に合う。Info.plist は手書き(project.yml の INFOPLIST_FILE が参照)なので生成元はそのファイル。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Info.plist に Developer Tools を追加し、InfoPlistTests に declaresApplicationCategory を追加。swift test --filter InfoPlistTests で 8 件(QuickLookInfoPlistTests 4 件含め)通過。
<!-- SECTION:FINAL_SUMMARY:END -->
