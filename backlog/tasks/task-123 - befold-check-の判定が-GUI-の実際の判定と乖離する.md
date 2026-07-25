---
id: TASK-123
title: befold --check の判定が GUI の実際の判定と乖離する
status: To Do
assignee: []
created_date: '2026-07-24 22:21'
labels:
  - cli
  - bug
dependencies: []
priority: high
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で確認(CONFIRMED)。--check は GUI で開けるかを予測するためのコマンドだが、3 点で GUI と判定が乖離する。
1. CLICheckCommand.swift:35 で fileSize(at:) が nil のとき `?? 0` で 0 に強制され、サイズ超過ファイルでも「Can open / Size: 0 bytes」exit 0 になる(GUI 側は fileTooLarge で拒否)。
2. サイズ判定が raw バイト数のみで、GUI(ViewerLoadPipeline.loadFull)が非行指向タイプで行うデコード後 UTF-8 サイズの再チェックを行わないため、非 UTF-8 エンコーディングで判定が割れる(例: 9.5MB の Shift_JIS markdown がデコード後 14MB になるケース)。
3. 内容を一切読まないため、内容起因の GUI 拒否を予測できない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 fileSize が nil を返すファイルを openable と報告しない
- [ ] #2 非行指向タイプのサイズ判定が GUI のデコード後サイズ判定と一致する
- [ ] #3 乖離ケース(nil サイズ・非 UTF-8 大容量)のテストがある
<!-- AC:END -->
