---
id: TASK-269
title: macOS 14 では nativeBackedFileURL が no-op になる可能性を検証する
status: To Do
assignee: []
created_date: '2026-08-03 13:51'
labels:
  - performance
dependencies: []
priority: medium
ordinal: 460000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review high の PLAUSIBLE 指摘。Package.swift は .macOS(.v14)、project.yml も macOS 14.0 を宣言しているが、.github/workflows/ci.yml のテストは macos-26 でしか走らない。

nativeBackedFileURL は URL(fileURLWithPath:) が Swift native の文字列ストレージを保持することを前提にしているが、NSURL/CFURL 裏打ちの URL 実装ではそうならない。verifier が当該実装を強制して確認したところ、連続 UTF-8 の Swift 文字列を渡しても `URL(fileURLWithPath: s).path.isContiguousUTF8 == true` に対し `(NSURL(fileURLWithPath: s) as URL).path.isContiguousUTF8 == false` だった。

これが macOS 14 の実 Foundation にも当てはまるなら、macOS 14 のユーザーには TASK-265 のフリーズが残ったまま、エントリごとのパスコピーと URL 再構築のコストだけが増えることになる。FileListEntryTests の isContiguousUTF8 アサートは macos-26 でしか走らないため、CI では検出できない。

まず macOS 14 実機（または該当 SDK）で成立するかを確認し、成立するなら nativeBackedFileURL 側で裏打ちを保証できる実装に直すか、macOS 14 のサポート方針そのものを判断する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 macOS 14 の Foundation で nativeBackedFileURL が期待どおり native 裏打ちの URL を返すかどうかを実測で確認する
- [ ] #2 no-op になる場合、実装の修正かサポート方針の判断（どちらを採るか）を Notes に記録する
- [ ] #3 CI が deployment target を検証しない件について、対処するか許容するかを明記する
<!-- AC:END -->
