---
id: TASK-123
title: befold --check の判定が GUI の実際の判定と乖離する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:21'
updated_date: '2026-07-25 01:04'
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
- [x] #1 fileSize が nil を返すファイルを openable と報告しない
- [x] #2 非行指向タイプのサイズ判定が GUI のデコード後サイズ判定と一致する
- [x] #3 乖離ケース(nil サイズ・非 UTF-8 大容量)のテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化の検討: 3 つの乖離はいずれも CLICheckCommand が ViewerLoadPipeline の判定を独自に再実装していることに由来する。個別に 3 箇所を直すのではなく、判定そのものを GUI 経路へ委譲して実装元を 1 つにする。
2. CLICheckCommand.rejectReason を ViewerLoadPipeline.load 呼び出しへ置き換える(oneShotLoad: true / embedLocalImages: false)。
3. run() を async 化し、befold-cli を AsyncParsableCommand へ変更する。
4. detail 行のサイズ表示は nil を 0 に丸めず unknown と表示する。
5. 乖離ケース(サイズ不明の超過ファイル・デコード後に超過する Shift_JIS)のテストを先に書いて赤を確認してから実装する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
原因: 3 点の乖離はすべて同一の構造問題(判定ロジックの二重実装)から来ていた。CLICheckCommand.rejectReason(旧 L46-59)が ViewerLoadPipeline.load(L45-99)の判定を独自に再現しており、サイズ上限の定数は共有しているのに『何と比較するか』がズレていた。個別修正では同種のドリフトが再発するため、判定を GUI 経路へ委譲して実装元を 1 つにする方針をユーザーと合意のうえ採用した。

実装:
- CLICheckCommand.rejectReason を ViewerLoadPipeline.load への委譲に置き換えた。oneShotLoad: true でライブリロード用 dataHash 計算を省き、embedLocalImages: false で画像へ触れないようにしている。Outcome のマッピングは .chunked/.full(rejectReason: nil) → openable、.full(rejectReason:) → その理由、.missing → 段階 1・3 を通過後に消えた TOCTOU として unsupportedFormat。
- detail 行のサイズは fileSize が nil のとき 0 に丸めず 'Size: unknown' と表示する。
- run() の async 化に伴い befold-cli を AsyncParsableCommand へ変更。execute を @MainActor にしたことで内部の MainActor.assumeIsolated ラッパ 2 箇所が不要になり削除できた(副次的な単純化)。

代償(合意済み): --check がファイルを全量読むようになった(従来は先頭 8KB のみ)。--check は 1 パスあたり 1 回の実行であり、判定の正確さを優先した。

検証:
- 新規テスト 2 件を先に書き、実装前に両方が『Can open』を返して失敗することを確認した(TDD の赤)。
- swift test: 609 tests / 84 suites pass。swiftformat --lint: 0/179 files require formatting。
- 実バイナリでの end-to-end 確認: 11MB の md → 'This file is too large to display.' exit 1。raw 9,000,000 バイト(上限内)の Shift_JIS md → デコード後 13.5MB のため拒否 exit 1(これが description の乖離 2 そのもの)。通常の mmd → 'Can open' exit 0、存在しないパス → exit 1。

補足: description の乖離 3(内容起因の GUI 拒否を予測できない)は AC に含まれていないが、委譲により自動的に解消した(デコード不能ファイルや読み取り不能なバイナリも GUI と同じ理由で拒否されるようになった)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
--check の判定を独自実装から GUI と同じ ViewerLoadPipeline.load への委譲へ置き換え、判定の実装元を 1 つにした。これにより description の 3 つの乖離(サイズ不明ファイルの誤 openable 報告・デコード後サイズの見落とし・内容起因の拒否の予測不能)が同時に解消し、同種のドリフトが構造的に再発しなくなった。サイズ表示も nil を 0 に丸めず unknown と出す。付随して befold-cli を AsyncParsableCommand へ変更し、execute の @MainActor 化で MainActor.assumeIsolated ラッパ 2 箇所を削除した。検証は乖離 2 ケースの新規テスト(実装前に赤を確認)、swift test 609 tests / 84 suites pass、および実バイナリでの end-to-end 確認(raw 9MB の Shift_JIS md がデコード後 13.5MB として正しく拒否される)。
<!-- SECTION:FINAL_SUMMARY:END -->
