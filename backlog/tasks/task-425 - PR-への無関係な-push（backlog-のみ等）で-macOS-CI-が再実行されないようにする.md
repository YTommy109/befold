---
id: TASK-425
title: PR への無関係な push（backlog のみ等）で macOS CI が再実行されないようにする
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-10 08:41'
updated_date: '2026-08-10 09:03'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 前提を確認する: main の branch protection に required_status_checks が無いこと（gh api で確認済み）。スキップしたジョブが PR をブロックしない根拠にする。
2. ci.yml に軽量な changes ジョブ（ubuntu）を足し、その push で実際に変わったファイルを判定する。pull_request の synchronize では payload の before...after を gh api compare で比較し、それ以外（opened/reopened、main への push、schedule、force-push で before が解決できない場合）は fail-open で true にする。
3. build-and-test / js-test を changes の出力で条件付けし、無関係な push ではスキップする。
4. concurrency をワークフローレベルからジョブレベルへ移す。スキップされたジョブは concurrency グループに入らないため、無関係な push が進行中の重いジョブを巻き添えキャンセルしなくなる（今回の実害の直接原因）。
5. actionlint で構文を検証し、判定ロジックをローカルで（compare の JSON をモックして）確かめる。実挙動は PR 上で backlog のみの push と BefoldApp を触る push の 2 通りで確認する。
6. site.yml / verify-dmg.yml へ同じ対処が要るかを起動履歴で確認し、判断を Implementation Notes に残す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装（未 push）:
- ci.yml に changes ジョブ（ubuntu）を追加。pull_request の synchronize では payload の before...after を gh api compare で比較し、BefoldApp/ か .github/workflows/ci.yml を含むかで app 出力を決める。synchronize 以外・compare 失敗（force-push で before が解決できない等）は fail-open で true。
- build-and-test / js-test を needs: changes + needs.changes.outputs.app == 'true' で条件付け。
- concurrency をワークフローレベルからジョブレベル（build-and-test / js-test / thread-sanitizer それぞれ別グループ）へ移動。スキップされたジョブはグループに入らないため、無関係な push が進行中の重いジョブを巻き添えキャンセルしない。

検証:
- actionlint: リポジトリ全ワークフローで指摘ゼロ。
- 判定の正規表現をローカルで実測: backlog のみ→false / BefoldApp 配下→true / .github/workflows/ci.yml→true / ci.yml.bak→false / docs/BefoldApp/x.md→false / backlog と BefoldApp の混在→true / 空→false。
- main の branch protection には required_status_checks が設定されていない（gh api で確認）。スキップされたジョブが PR をブロックしないことの根拠。

他ワークフローの判断:
- site.yml: test ジョブは ubuntu で安価なため、push 単位のスキップは入れない。ただし paths に列挙していた BefoldApp/befold/App/MainMenuBuilder.swift が、分割で生まれた MainMenuBuilder+ViewMenu.swift を拾えずショートカットのずれ検知が起動しない穴があったため、MainMenuBuilder*.swift の glob へ広げた（本タスクのスコープ外の発見。ユーザーに報告済み）。
- verify-dmg.yml: 同じ per-push 評価の問題はあるが、対象が release.yml / verify-dmg.yml / create-dmg.sh と狭く、実害が小さいため対処しない。

未確認: 実挙動（backlog だけの push でスキップされること、BefoldApp を触る push で走ること）は PR 上でまだ確認していない。

実挙動の検証（PR #461）: opened イベントでは changes が 4 秒で success（app=true）となり build-and-test / js-test が起動することを確認。続けて backlog のみの push を 1 件行い、(a) build-and-test がスキップされること、(b) 進行中の build-and-test が巻き添えキャンセルされないことを確認する。
<!-- SECTION:NOTES:END -->
