---
id: TASK-255
title: GitCommandRunner の terminationGrace を注入可能にしテストの猶予待ちを短縮する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-01 13:42'
updated_date: '2026-08-02 00:32'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 450050
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-244 の実測で、テスト全体のクリティカルパスが GitCommandRunnerResourceLeakTests(13.0s、2 位に 2.3 秒差の単独律速)であり、その支配項が releasesResourcesWhenWriteEndSurvivesTermination の 7.14s であると判明した。
7.14s は GitCommandRunner.swift:34 の terminationGrace = 5 に由来する構造的な待ち(hangingBudget 2 + grace 5)。このテストは「孫を殺し切れず EOF が永遠に来ない経路でも猶予切れで資源が返る」ことを検証するため、猶予の満了を待つこと自体が検証であり、テスト側の工夫では縮められない。
terminationGrace をイニシャライザ注入可能にし(既定値は現行の 5 秒で本番挙動は不変)、テストで 0.5 秒程度に縮めれば 7.14s→約 2.2s、leak スイートは約 7.8s となり全体の律速から外れる。全体では約 2.3〜2.8 秒の短縮見込み(短縮後の床は ViewerStoreIntegrationTests の 10.76s)。
注意: TASK-226(GitCommandRunner の async 化・GitCommandFileIndex の actor 化)と同じファイルを触るため、着手時に合流させるか順序を決めること。猶予の待ち方自体が async 化で変わる可能性がある。
参考: TASK-244 のレビューで得られたスイート別実測(全体実行時) — GitCommandRunnerResourceLeakTests 13.03s / ViewerStoreIntegrationTests 10.76s / ViewerRendererContentUpdateTests 10.42s / ViewerRendererOneShotTests 9.97s
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 terminationGrace が注入可能になり、既定値は現行と同じで本番挙動が変わらない
- [x] #2 releasesResourcesWhenWriteEndSurvivesTermination が短い猶予で同じ不変条件(猶予切れで fd とスレッドが返る)を検証している
- [x] #3 GitCommandRunnerResourceLeakTests が全体のクリティカルパスから外れることを実測で確認する
- [x] #4 swift test が全てグリーン
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測(実装者・レビュー担当双方で確認):
- releasesResourcesWhenWriteEndSurvivesTermination: 7.14s → 2.6s
- GitCommandRunnerResourceLeakTests スイート: 13.0s → 8.245s
- フル swift test: 約 13.3s → 約 10.0s(その後の他タスク完了と合わせ最終的に 9.25s)
- 新しいクリティカルパス: ViewerStoreIntegrationTests(約 10.0s)。見立てどおり律速から外れた
数字の整合(レビューによる検証): deadline = timeout + terminationGrace なので、旧は hangingBudget 2 + 5 = 7 秒(実測 7.14s)、新は 2 + 0.5 = 2.5 秒(実測 2.6s)。差分 4.5 秒がそのまま短縮量。
検証の意味が変わっていないこと(レビューによる確認): このテストは escapesProcessGroup: true の孫が書き込み端を握り続ける構成のため EOF は構造的に永遠に来ない。資源が返る経路は猶予切れしかなく、最後の 2 つの waitUntil は猶予が満了して初めて成立する。したがって「猶予が切れる前にテストが終わる」状態にはなり得ず(切れなければ waitUntil の Issue.record で落ちる)、猶予の長さは待ち時間だけを決めて不変条件には影響しない。
TASK-226 との関係(レビューによる確認): terminationGrace は「打ち切り後に読み取りスレッドを何秒待つか」という値であって、同期/非同期どちらの設計でも必要な概念。init 引数が 1 つ増えるだけで async 化の構造に制約を与えないため、スコープを注入だけに限定した判断は妥当。
資源残留系の基準線検証への影響なし: 短い猶予を注入しているのは当該テスト内に閉じた 1 インスタンスのみで、他の leak テストは既定 5 秒のまま。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitCommandRunner の terminationGrace をイニシャライザ注入可能にした(既定値は現行の 5 秒で本番挙動は不変)。テストで 0.5 秒を注入することで、クリティカルパスだった資源残留テストが 7.14 秒 → 2.6 秒、スイートが 13.0 秒 → 8.245 秒となり、全体の律速から外れた。フル swift test は約 13.3 秒 → 約 10.0 秒。
一連のテストメンテナンス作業(TASK-244〜257)の中で、実測に基づいて CI 実行時間を短縮できた唯一のタスク。他は実測の結果ほぼ寄与しないと判明している。
猶予を縮めても検証の意味は変わらない(EOF が構造的に来ない構成のため、資源が返る経路は猶予切れしかなく、待機は猶予満了後に初めて成立する)ことをレビューで確認済み。
検証: swift build 警告なし、フル swift test 3 回連続グリーン(951 tests / 142 suites)。レビュー承認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
