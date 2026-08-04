---
id: TASK-1.4
title: ViewerStore を静的読込パイプラインと監視・永続化オーケストレーションに分離する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:38'
updated_date: '2026-07-18 11:19'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/212
parent_task_id: TASK-1
priority: medium
ordinal: 6400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #212 から移行。ViewerStore（307行）の読込パイプライン（computeLoad 周辺）にアプリ専用の関心（ファイル監視・UserDefaults 永続化・ウィンドウクローズ連動）が同居しており、静的1回描画だけが欲しい QuickLook から再利用できない。二層化して静的読込モードを提供する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 読込パイプラインが watcher・UserDefaults・onFileGone から分離されている
- [x] #2 QuickLook から静的読込のみのモードで使える
- [x] #3 既存テスト（ViewerStoreTests 34件）が維持されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. computeLoad/LoadOutcome は既に self 非依存の nonisolated static/enum であり、単純化の検討の結果、新しい状態や分岐を増やす再設計は不要。既存ロジックをそのまま BefoldKit へ「昇格」させるだけで AC1/AC2 を満たせる。
2. BefoldApp/BefoldKit/ViewerLoadPipeline.swift を新規作成し、ViewerStore.LoadOutcome enum と private static computeLoad をロジック無変更のまま public struct/enum ViewerLoadPipeline として移設する（ChunkedReaderFactory closure 型も public typealias として同居させる）。
3. ViewerStore.swift から移設元の private 宣言を削除し、performLoad/apply から BefoldKit.ViewerLoadPipeline.load(...) / .Outcome を参照するよう置き換える。既存の ChunkedReaderFactory typealias は BefoldKit 側への alias として残し、テストヘルパー(ViewerStoreTests.swift:55)のシグネチャを壊さない。
4. swift build / swift test で ViewerStoreTests 34件を含む既存テストが通ることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
computeLoad/LoadOutcome は既に self 非依存の nonisolated static/enum だったため、単純化の検討結果として新しい抽象・状態は追加せず、ロジック無変更のまま BefoldKit/ViewerLoadPipeline.swift (public enum ViewerLoadPipeline, Outcome, ChunkedReaderFactory) へ移設。
ViewerStore.swift は performLoad/apply から ViewerLoadPipeline.load(...)/.Outcome を参照するよう置換し、ChunkedReaderFactory typealias は BefoldKit 側への alias として維持(テストヘルパー ViewerStoreTests.swift:55 のシグネチャは無変更)。
検証: swift build 成功(警告なし)。swift test --filter ViewerStore で ViewerStore 関連 7 suite 54 tests 全成功。swift test でリポジトリ全体 371 tests 全成功。
grep で ViewerLoadPipeline.swift に FileWatcher/UserDefaults/onFileGone への実参照(コメント以外)が無いことを確認し、watcher・永続化・削除通知から分離済みであることを確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore の読込パイプライン(computeLoad/LoadOutcome)を BefoldKit/ViewerLoadPipeline.swift の public enum として抽出し、watcher・UserDefaults・onFileGone のオーケストレーションから分離した。ロジックは無変更のまま移設(ChunkedReaderFactory は alias で維持)。swift build 成功、swift test で ViewerStore 関連54件を含む全371件のテストが成功することを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
