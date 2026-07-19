---
id: TASK-72.2
title: FileType に QuickLook 対象拡張子集合を追加する
status: To Do
assignee: []
created_date: '2026-07-19 06:44'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileType.swift の既存分類(レンダリング5種+codeExtensionLanguages)から、PDF・画像を除いた QuickLook 対象拡張子集合を返す純粋関数を追加する。FileType の分類ロジックを単一情報源とし、QuickLook側で独自に拡張子リストを持たないようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 quickLookSupportedExtensions(仮称)が .mmd/.mermaid, .md/.markdown, .svg, .html/.htm, .csv/.tsv, および codeExtensionLanguages の全拡張子を返す
- [ ] #2 quickLookSupportedExtensions が pdf/png/jpg/jpeg/gif/webp/bmp/ico を含まない
- [ ] #3 拡張子集合を検証するユニットテストがある
<!-- AC:END -->
