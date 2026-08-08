---
id: TASK-384
title: 紹介サイトのキーボードショートカット表示を実装と同期させる
status: To Do
assignee: []
created_date: '2026-08-08 14:09'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 642000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
紹介サイト（site/）は LP と TASK-376 で追加する詳細ページの双方で、キーボードショートカット（cmd+P / cmd+S / cmd+U / cmd+L / cmd+F / cmd+[ / cmd+] など）を手書きで記載している。実装側の割り当て（BefoldApp の MainMenuBuilder ほか）を変更しても site 側は落ちないため、ずれても気づけない二重管理になっている。

TASK-376 では対応ファイルタイプ表について FileType.swift を情報源としたずれ検知テストを導入した（site/test/file-types.test.ts）。同じ手口をショートカットにも適用する。

TASK-376 の /review-design で『AC は対応ファイルタイプ表のみを要求しており、Swift 側の解析対象をもう 1 系統増やすとスコープが広がる』として分離したもの。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 site 側に記載したショートカットが実装の割り当てとずれた場合に落ちるテストがある
- [ ] #2 検証対象は LP と詳細ページの両方をカバーする
<!-- AC:END -->
