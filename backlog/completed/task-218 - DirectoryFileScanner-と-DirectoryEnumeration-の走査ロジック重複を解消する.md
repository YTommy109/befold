---
id: TASK-218
title: DirectoryFileScanner と DirectoryEnumeration の走査ロジック重複を解消する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 07:43'
updated_date: '2026-07-31 08:15'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/BefoldKit/DirectoryEnumeration.swift
  - BefoldApp/BefoldKit/QuickOpenCandidates.swift
priority: low
ordinal: 298000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-209 でディレクトリ列挙・分類・自然順ソートを BefoldKit の DirectoryEnumeration に単一実装化し、SupportedFileResolver と DirectoryLister が委譲する形にした。一方 Quick Open の候補走査を担う DirectoryFileScanner は別実装として残っており、同種の列挙・隠しファイル判定・フィルタを重ねて持っている可能性がある。TASK-209 着手時点では DirectoryFileScanner が TASK-205（Quick Open 非同期化）の担当領域だったため手を付けていない。両 PR がマージされた後の実態を確認し、実際に重複していれば DirectoryEnumeration に寄せる。重複が見かけ倒しで再帰走査・件数上限など Quick Open 固有の要件が正当な差分であれば、その理由をノートに記録して現状維持とする。着手前に PR #351 (TASK-205) と PR #355 (TASK-209) がマージ済みであることを確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 DirectoryFileScanner と DirectoryEnumeration の重複範囲が調査され、統合するか現状維持かの判断根拠がノートに記録されている
- [x] #2 統合する場合、Quick Open とサイドバー・CLI --check の既存挙動が変わらない（既存テストが通る）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. DirectoryFileScanner / DirectoryEnumeration / HiddenFileRule と呼び出し元を読み、走査範囲・隠し判定・分類・ソートの各軸で重複の実態を特定する
2. 統合するか現状維持かを判断し、根拠をノートに記録する
3. (現状維持と判断) 統合しない理由を DirectoryFileScanner の doc コメントに残す
4. swift build / swift test で挙動不変を確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 調査結果と判断: 統合せず現状維持

PR #351 (TASK-205) / #355 (TASK-209) マージ後の実態を確認した。両者は「ディレクトリを列挙してファイルを集める」点で表面的に似ているが、4 つの軸すべてで要件が食い違っており、いずれも既存コメントに理由が明記された意図的な差分だった。

| 軸 | DirectoryEnumeration (サイドバー/CLI) | DirectoryFileScanner (Quick Open) |
| --- | --- | --- |
| 走査範囲 | 直下 1 階層のみ。列挙失敗は空を返す | 再帰。深さ 8 / 件数 10,000 の上限。列挙失敗・打ち切りを isTruncated で呼び出し元に報告 |
| 戻り値 | (folders: [URL], files: [URL]) の分類済み組 | DirectoryScanResult(files, isTruncated)。フォルダー分類自体が不要 |
| 隠し判定 | FileManager .skipsHiddenFiles(chflags hidden 込み) | HiddenFileRule(ドット始まりのみ) |
| シンボリックリンク | fileReader.isDirectory で実体を追いディレクトリ扱い | 追わずファイル候補 1 件として扱う(循環回避) |
| 並び | localizedStandardCompare の自然順(表示順) | ロケール非依存の生比較(打ち切り位置を実行環境で変えないため) |
| 依存 | FileReading を DI | FileManager 直・除外ディレクトリ名 |

### 「ドリフトすると実害が出る部分だけ共有する」中間解も採らない
- **隠し判定**: すでに HiddenFileRule が Quick Open 側の単一情報源として存在する。HiddenFileRule.swift のコメントどおり、Quick Open の候補には git 追跡索引由来の「文字列だけ」の候補が混ざるため、URL を stat する .skipsHiddenFiles では走査・索引・パスモードでフィルタの意味がずれる。**あえて別ルールにしている**ので共有してはいけない。
- **ソート**: DirectoryFileScanner のコメントどおり、自然順ではなくロケール非依存比較を使うのは打ち切り位置の決定性のため。Quick Open の最終表示順はスコアリングが決めるので自然順は不要。sortedByFileName() を流用すると決定性が壊れる。

### 統合した場合のコスト
共通化するには recursive/maxDepth/maxCount/excludedNames/hiddenRule/symlinkPolicy/sortComparator/truncation 報告の 8 パラメータを 1 つの API に持ち込むことになり、どちらの呼び出し元にとっても大半が無関係。可読性が下がるだけで実利がない。

### 実施したこと
統合の代わりに、DirectoryFileScanner の doc コメントに「DirectoryEnumeration と意図的に統合していない理由」を上表の形で残し、将来同じ検討が蒸し返されないようにした。挙動変更なし(コメント追加のみ)。swift build 成功、swift test 935 tests / 128 suites すべて通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DirectoryFileScanner と DirectoryEnumeration の重複を調査し、統合せず現状維持と判断した。走査範囲(1階層/再帰+上限+truncated報告)、隠し判定(.skipsHiddenFiles/HiddenFileRule)、シンボリックリンク方針、ソート(自然順/ロケール非依存)の 4 軸すべてで要件が食い違い、いずれも既存コメントに理由が明記された意図的な差分だった。隠し判定とソートは Quick Open 側の一貫性のため**あえて別ルール**であり、部分共有も有害。統合の代わりに DirectoryFileScanner の doc コメントへ「意図的に統合していない理由」を対比表で残した(挙動変更なし)。swift build 成功、swift test 935 tests / 128 suites 全通過で挙動不変を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
