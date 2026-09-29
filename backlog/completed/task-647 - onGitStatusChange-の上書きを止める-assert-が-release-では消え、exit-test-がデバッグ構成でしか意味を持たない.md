---
id: TASK-647
title: onGitStatusChange の上書きを止める assert が release では消え、exit test がデバッグ構成でしか意味を持たない
status: Done
assignee:
  - '@claude'
created_date: '2026-09-27 07:24'
updated_date: '2026-09-27 08:21'
labels: []
dependencies: []
references:
  - BefoldApp/befold/Viewer/FileListModel.swift
  - BefoldApp/befoldTests/SidebarNavigatorReviewExpansionTests.swift
priority: low
ordinal: 847000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-641（commit 33f904a3）で `FileListModel.onGitStatusChange` の `willSet` に `assert(onGitStatusChange == nil, ...)` を置き、`SidebarNavigatorReviewExpansionTests.overwritingGitStatusSubscriberTraps` が `#expect(processExitsWith: .failure)` でそれを確かめている。`/code-review high` が構成依存を指摘した。

## 現状（検証済み）

- `assert` は `-O`（release）でコンパイル時に除去される。`swift test -c release` では `willSet` が no-op になり、子プロセスは正常終了するので exit test は失敗する。
- CI（`.github/workflows/ci.yml`）の `swift test` は 3 箇所ともデバッグ構成（`-c release` 指定なし、1 つは `--sanitize=thread`）なので今日は通る。
- ただし TASK-641 の AC「実行時に assert で止まる」と test 名が保証するのはデバッグビルドだけで、その限定が doc にも test にも書かれていない。出荷ビルドで上書きされた場合は黙って展開が止まる（TASK-641 が塞ぎたかった事故そのもの）。

## 方向

どちらかを選び、理由を Notes に残す。(a) 出荷ビルドでも止めたいなら `precondition` にする（このスロットへの 2 回目の代入はプログラミングエラーなので妥当）。(b) デバッグ限定でよいなら `#if DEBUG` でテストを囲い、doc に「デバッグ構成のみ」と書く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `swift test -c release` で `overwritingGitStatusSubscriberTraps` が失敗しない（precondition 化で通るか、`#if DEBUG` で除外されるか）
- [x] #2 `onGitStatusChange` の doc コメントが、上書きの検知がどの構成で働くかを述べている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. willSet の assert を precondition へ置き換え、出荷ビルドでも上書きを止める (方向 a)
2. doc コメントとテストの doc に、全構成で止まることを明記
3. swift test -c release で overwritingGitStatusSubscriberTraps を確認、デバッグでも確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方向 (a) を採用: willSet の assert を precondition に置き換えた。このスロットへの 2 回目の代入はプログラミングエラーで、出荷ビルドで黙って展開が止まることこそ TASK-641 が塞ぎたかった事故のため、release でも止める。#if DEBUG でテストを除外する (b) は保証をデバッグに限定するだけなので採らない。

検証（実測）:
- swift test -c release はテストターゲットがそもそもビルドできない（既存: DirectHTMLModeController.simulateForTesting 等が #if DEBUG 内）。assert の除去は DEBUG フラグではなく -O で決まるため、swift test -c release -Xswiftc -DDEBUG --filter overwritingGitStatusSubscriberTraps で -O 下を再現した。
- precondition: pass / assert に戻した対照: fail（exit test が正常終了を検知）→ 構成依存が解消したことを確認。
- デバッグ: SidebarNavigatorReviewExpansionTests 10 件 pass。swiftlint 対象 2 ファイル 0 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
onGitStatusChange の上書き検知を assert から precondition へ変え、release（-O）でも止まるようにした。doc コメントに全構成で働く旨と理由を明記。-O 下での pass と、assert に戻すと fail することを実測で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
