---
id: TASK-425
title: PR への無関係な push（backlog のみ等）で macOS CI が再実行されないようにする
status: To Do
assignee: []
created_date: '2026-08-10 08:41'
labels:
  - ci
dependencies: []
priority: medium
type: task
ordinal: 505500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状、PR ブランチへ backlog/ だけの commit を push しても .github/workflows/ci.yml（build-and-test / js-test）が再トリガされ、macOS ランナーで swift build + swift test が丸ごと走り直す。

原因（実測: 2026-08-10、PR #460）:
- ci.yml の pull_request トリガは on.pull_request.paths を 'BefoldApp/**' と '.github/workflows/ci.yml' に絞っている（.github/workflows/ci.yml:9-13）。
- しかし GitHub の pull_request イベントの paths フィルタは、その push の差分ではなく PR 全体の変更ファイル集合で評価される。PR #460 は BefoldApp/** を含むため、backlog/ だけを足した push（69de696）でも条件が成立し、run 31371041640 が起動した。
- さらに concurrency.group が ci-<ref> かつ cancel-in-progress: true のため（ci.yml:19-21）、その時点で走っていた build-and-test（再実行中だったもの）が巻き添えでキャンセルされた。実測ではこれで 1 回、テスト結果を得る前にランを失っている。

同じ性質は site.yml / verify-dmg.yml の paths にもある（未確認: それぞれの実害の大きさは測っていない。ci.yml と同じ理屈が当てはまるはずで、gh run list の起動履歴で確認できる）。

やりたいこと: PR 中の「その push で実際に変わったファイル」に基づいて重いジョブをスキップできる形にする。実現方法（dorny/paths-filter 等のアクションでジョブ単位に判定する / 重いジョブを別ワークフローへ分ける / 現状を許容して concurrency の巻き添えだけを避ける）は着手時に比較して決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PR ブランチへ backlog/ や docs/ だけの commit を push したとき、macOS ランナーのジョブ（build-and-test）が起動しないか、起動しても即スキップして終わる
- [ ] #2 BefoldApp/** を変更する push では従来どおり build-and-test が走る（スキップの条件が広すぎて検証が抜けることがない）
- [ ] #3 スキップされたジョブが必須チェックとして PR をブロックしない（required check の扱いを確認して記録してある）
- [ ] #4 採用した方式と、他ワークフロー（site.yml / verify-dmg.yml）へ同じ対処が要るかどうかの判断が Implementation Notes に残っている
<!-- AC:END -->
