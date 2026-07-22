---
id: TASK-97
title: ルートの OpenCLIOptions がサブコマンド前の open 専用フラグを黙って捨てる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-22 13:37'
updated_date: '2026-07-22 13:58'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/BefoldRootCommand.swift
priority: high
type: bug
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(inselberg-ramada ブランチ)で検出。TASK-94.4 でルートコマンドに `@OptionGroup var openOptions: OpenCLIOptions` を追加した結果、`befold --hidden-files check path` や `befold --source bookmark add dir/` のようにサブコマンド名の前に open 専用フラグを置くと、ルートがフラグを消費して check/bookmark へは渡らず、警告もエラーも出ずに無視される。変更前はこれらはルートオプションではなかったため、同じ入力はデフォルトの open にフォールスルーしていた。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 open 専用フラグを check/bookmark と組み合わせた場合、黙殺されずエラーまたは明確な挙動になる
- [x] #2 検証エラーの帰属(どのコマンドのオプションか)が正しく表示される
- [x] #3 回帰テストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldRootCommand から @OptionGroup var openOptions: OpenCLIOptions を削除する(open 専用フラグはサブコマンドの前に置かれるとパースエラーになるようにする) 2. ルート --help の discussion はすでに befold open --help を案内しているため、オプション表示は open --help に委ねる 3. 回帰テストを追加する(--hidden-files check path がエラーになることを確認)
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldRootCommand から @OptionGroup var openOptions: OpenCLIOptions を削除。open 専用フラグがサブコマンド名の前にあると、サブコマンド名がパスとして解釈される明確な挙動になり、黙殺されなくなった。インテグレーションテスト・ユニットテストを更新。
<!-- SECTION:FINAL_SUMMARY:END -->
