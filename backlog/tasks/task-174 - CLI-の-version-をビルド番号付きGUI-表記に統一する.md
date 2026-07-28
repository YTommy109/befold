---
id: TASK-174
title: CLI の --version をビルド番号付き(GUI 表記)に統一する
status: To Do
assignee: []
created_date: '2026-07-28 00:43'
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
- [ ] #1 befold --version が GUI と同じ "<ShortVersion> (<BundleVersion>)" 形式で表示される
- [ ] #2 CFBundleVersion が取得できない(バンドル外/SPM 単体ビルド等)場合の表示フォールバックが定義され、クラッシュや空括弧にならない
- [ ] #3 GUI 側のバージョン表記との一貫性が担保される(共通のフォーマット箇所を用いる等)
- [ ] #4 AppVersion まわりのテストがビルド番号付き表記を検証する
<!-- AC:END -->
