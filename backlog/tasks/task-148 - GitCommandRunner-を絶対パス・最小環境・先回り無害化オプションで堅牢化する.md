---
id: TASK-148
title: GitCommandRunner を絶対パス・最小環境・先回り無害化オプションで堅牢化する
status: Done
assignee: []
created_date: '2026-07-25 11:30'
updated_date: '2026-07-25 12:13'
labels:
  - path-reference
  - security
dependencies: []
priority: medium
type: task
ordinal: 224000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セキュリティレビュー指摘（低 L-3 / L-4）。(1) GitCommandRunner.swift L38 が /usr/bin/env git + 無加工の継承環境で実行しており、PATH 先頭の偽 git や GIT_CONFIG_COUNT/GIT_CONFIG_KEY_*・GIT_DIR 等の環境変数が -c 無害化を上書きしうる。(2) 現行の hardeningOptions は rev-parse/ls-files の 2 コマンドに対しては十分だが、将来コマンド追加時に core.pager・diff.external・textconv・credential.helper 等が新たな実行経路になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 executableURL を /usr/bin/git に固定し、process.environment を最小集合（PATH 固定、GIT_* 除去）に差し替える
- [x] #2 hardening に `-c core.pager=cat`（または --no-pager）、GIT_PAGER=cat、GIT_TERMINAL_PROMPT=0 を追加する
- [x] #3 GitCommandRunnerTests で環境最小化・無害化オプションの内容を固定する
- [x] #4 core.fsmonitor の値を空文字のままにする判断（false にしない理由）をコメントで明文化する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. executableURL を /usr/bin/git 固定にする（GUI 起動時に env が解決するのも実質 /usr/bin/git なので実効バイナリは変わらない）
2. process.environment を最小集合に固定（PATH 固定 + HOME のみ残す + GIT_TERMINAL_PROMPT=0）。GIT_CONFIG_COUNT/KEY/VALUE・GIT_DIR 等が -c を上書きする経路を断つ
3. hardeningOptions に --no-pager を追加（GIT_PAGER=cat より強く、ページャプロセス自体を起動しない）
4. core.fsmonitor= の空文字は維持し、false にしない理由をコメント化する。git 2.54 では false は boolean だが、legacy（2.37 未満）では core.fsmonitor はフックパスであり false が相対パス扱いになるため、リポジトリ同梱の実行ファイル false を実行する新たな穴になりうる
5. テスト: 引数列に --no-pager が入ることの位置固定 + 呼び出し元の GIT_* を引き継がないことの検証（無害な GIT_CONFIG_COUNT=0 を立てて確認。並行実行中の他テストの git を壊さない値を選ぶ）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装:
- executableURL を /usr/bin/git に固定。GUI 起動時は既定 PATH のため env git も同じ実体を解決しており実効バイナリは変わらない（CLI 起動でユーザーのシェル PATH を継承する経路だけが塞がれる）。
- process.environment を PATH（固定）/ HOME / GIT_TERMINAL_PROMPT=0 の 3 つに差し替え。HOME を残すのはユーザー自身の ~/.gitconfig が信頼できる設定であり、落とすと git が意図しない既定へ倒れるため。GIT_PAGER=cat は --no-pager と環境総入れ替えで不要になったため入れていない（ページャプロセス自体を起動しないぶん --no-pager の方が強い）。
- hardeningOptions の先頭に --no-pager を追加。

core.fsmonitor を false にしない判断（AC を差し替え）: 実機 git 2.54.0 では false は boolean として解釈されマーカーは作られないことを確認したが、core.fsmonitor が監視フックの「パス」だった git 2.37 未満では false が相対パス扱いになり、リポジトリに同梱された false という実行ファイルを起動しうる。これは本無害化が塞ごうとしている攻撃そのものであるため、両方の解釈で無効に落ちる空文字を維持し、その理由をコード内コメントに明記した。
検証: swift test 687 tests（Integration 含む）全パス。GitRepositoryTests / GitCommandRunnerTests は実 git をこのランナー経由で叩くため、/usr/bin/git 固定と最小環境で git が正常動作することの実証になっている。環境テストは呼び出し元に GIT_CONFIG_COUNT=0（追加設定なしの宣言で並行テストに無害）を立て、返る環境に現れないことで「継承していない」ことを検証している。swift build（SwiftLint 込み）、swiftformat 差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git 実行を /usr/bin/git 固定 + 最小環境（PATH 固定・GIT_* 非継承・GIT_TERMINAL_PROMPT=0）に変更し、hardening に --no-pager を追加した。PATH 差し替えによる偽 git と、-c を上書きしうる GIT_* 環境変数の経路を塞いでいる。core.fsmonitor は旧 git での相対パス解釈のリスクから空文字を維持し理由を明文化。swift test 687 件全パスで実 git 動作を確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
