---
id: TASK-404
title: ディレクトリ列挙の失敗を表現できるようにする
status: To Do
assignee: []
created_date: '2026-08-10 03:09'
labels: []
dependencies: []
priority: low
type: task
ordinal: 661000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`DirectoryEnumeration.sortedContents` は列挙の失敗を `try?` で握り潰し、空の組を返す（doc に「列挙に失敗した場合は空の組を返す」と明記）。`DirectoryLister.listEntriesAsync` / `childEntriesAsync` も throws でも Optional でもない。

このため呼び出し側は「空のフォルダ」と「列挙失敗（権限が無い・消えた）」を区別できない。

## いつ困るか

TASK-361.3 でサイドバーのツリー展開の子リスト状態を設計した際、`.failed` を置こうとしたが**到達不能**になるため落とした（到達不能な状態を型に置くと「`.failed` が来ない = 失敗が無い」と読めてしまう）。結果、権限の無いフォルダを展開すると「空のフォルダ」として表示される。

## 波及範囲

`sortedContents` の消費側は GUI（DirectoryLister）と CLI（SupportedFileResolver 経由）の両方にあるため、失敗を表現できる形（Result / Optional）へ変えると全消費側に波及する。361.3 のスコープには含めなかった。

## 参考

- `BefoldApp/BefoldKit/.../DirectoryEnumeration.swift`
- `BefoldApp/befold/App/SidebarExpansion.swift` の `Children` の doc（この判断の記録）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 列挙失敗と「空のディレクトリ」が呼び出し側で区別できる
- [ ] #2 GUI・CLI 双方の消費側が新しい形へ追従している
- [ ] #3 サイドバーのツリー展開が、列挙失敗を「空のフォルダ」として表示しない
<!-- AC:END -->
