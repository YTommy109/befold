---
id: TASK-58
title: ファイルサイズが maxChunkBytes と完全一致し末尾改行がないとき偽のトランケーションバナーが一瞬表示される
status: To Do
assignee: []
created_date: '2026-07-18 08:13'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
テキスト長が maxChunkBytes (1MB) と完全一致し末尾に改行がない場合、advanceByLines/advanceRespectingQuotes が forcedSplit=true + endIndex を返す。readNextChunk は resumeIndex=endIndex かつ isAtEnd=false を設定するため、全内容を含むチャンクなのにトランケーションバナーが表示される。次の readNextChunk で空文字列 + isAtEnd=true が返り、バナーが消える。結果としてバナーが一瞬フラッシュする。
コードレビュー（arch-saguaro ブランチ、2026-07-18）で発見。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ファイルサイズが maxChunkBytes と完全一致し末尾改行がない場合にトランケーションバナーが表示されない
- [ ] #2 forcedSplit=true かつ endIndex の場合を正しくハンドルするユニットテストが追加されている
<!-- AC:END -->
