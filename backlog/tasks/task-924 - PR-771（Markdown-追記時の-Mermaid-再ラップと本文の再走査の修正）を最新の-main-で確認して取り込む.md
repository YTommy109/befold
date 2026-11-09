---
id: TASK-924
title: 'PR #771（Markdown 追記時の Mermaid 再ラップと本文の再走査の修正）を最新の main で確認して取り込む'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T04:58:00Z'
updated_date: '2026-11-09T07:53:00Z'
labels:
  - pr
  - ci
dependencies: []
references:
  - https://github.com/YTommy109/befold/pull/771
priority: high
ordinal: 889000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #771 はレビューの結果そのまま取り込む方針にした。ただし確認に 2 つの穴が残っている。(1) PR の CI は base 4771f4d0 で走っており、main はその後 12 コミット進んだ。viewer-src とバンドルは変わっておらず、試験マージでもコンフリクトは出ないので壊れている可能性は低いが、統合後の状態では CI を回していない。(2) レビューで確かめたのは Jest（修正を戻すと対応するテストが落ちることを含む）と、WKWebView に appendChunk を直接呼ぶ計測で、実際のアプリのスクロール追記とズーム操作は誰も試していない。PR の検証欄にも、Swift アプリ本体での確認は未実施とある。外部コントリビューターの PR で maintainerCanModify は true。PR への返信は今回は行わない判断なので、このタスクにも含めない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 最新の main へ PR を重ねた状態で CI の build-and-test（default / strict）と js-test が成功している
- [x] #2 段階読み込みが働く大きさの、Mermaid 図を複数含む Markdown を実際のアプリで開き、「続きを読み込む」で追記しても既存の図が縮まず、図ごとのズーム操作（+ / − / ラベルでのリセット）が既存の図と追記した図で独立して効く
- [x] #3 同じ文書で追記した範囲のパス参照がリンクとして解決されている
- [x] #4 PR #771 が main へマージされている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. origin/main に PR #771 の head（b5abbe25）を重ねたローカルの統合ブランチ verify/pr771-on-main を作る
2. 統合状態で Jest・バンドルの一致を確認し、アプリをビルドして実機で確認する（図の縮小なし・図ごとのズームの独立・追記範囲のパス参照の解決）
3. 同じ統合コミットを一時ブランチとして push し、ドラフト PR で CI を回す。PR 本体のブランチには触らない（workflow スコープが無く、allow_update_branch も無効で、コントリビューターのブランチでもあるため）
4. CI 成功を確認したら検証用 PR を閉じて一時ブランチを消し、PR #771 を squash マージする
5. main への push の CI を確認し、タスクを完了して backlog の変更を basin-juniper でコミットする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実機確認（2026-11-09、origin/main b118ab17 + PR head b5abbe25 の統合 1ad0bfe7 を xcodebuild Debug でビルド、CFFIXED_USER_HOME で設定を分離）。各 1000 行 4 ブロック・各ブロック先頭に Mermaid 図とパス参照を持つ Markdown を実アプリで開き、AX で「続きを読み込む」と各ボタンを押して測定した。図の縮尺は図内ノード P{n}N0 と P{n}N8 の縦距離。

追記 3 回（D0 を 125% にしてから開始）: D0 は 780 のまま、追記した D1〜D3 は 100% で 624。既存の図は縮まない。
図ごとのズーム: D3 に + を 2 回で 150% / 936、D1 に − で 75% / 468、D0 のラベル押下で 100% / 624。他の図の倍率と距離は変わらない。
パス参照: 追記 3 回目の範囲にある src/part3.md を実クリックすると、窓が part3.md へ移った。実クリックしたのはこの 1 件のみ。

統合状態の Jest は 23 スイート / 758 件成功、esbuild の再生成はバンドルと一致。

PR ブランチの更新は行わない: 2026-11-09 時点で main の #784 が ci.yml を変更しており、トークンに workflow スコープが無く、allow_update_branch も無効（TASK-908 と同じ制約）。統合コミットを一時ブランチのドラフト PR で CI にかける。

受け入れ条件 2 の「スクロールで追記」は起票時の誤りで、実際の追記は「続きを読み込む」ボタン（viewer-src/truncation.ts）で起きるため書き換えた。

CI: 統合コミット 1ad0bfe7 の検証用ドラフト PR #785（run 42579736148）で changes / type-group-size / js-test / build-and-test default・strict が success。確認後に #785 を閉じ、一時ブランチを削除した。

マージ: head b5abbe25 に固定して squash マージ（d83e5c68）。コントリビューターのブランチは削除していない。main への push の CI（run 42580750872）は thread-sanitizer を含めすべて success。

#785 の本文が #771 に言及しているため、#771 のタイムラインに相互参照が 1 件残る。#771 への返信はしていない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PR #771（Markdown 追記時の Mermaid 再ラップと本文の再走査の修正）を main へ取り込んだ（d83e5c68）。最新の main へ重ねた統合状態で CI と実機を確認した。実機では、追記しても既存の図が縮まず、図ごとのズームが独立して効き、追記範囲のパス参照をクリックするとファイルが開いた。main への push の CI も thread-sanitizer を含めすべて成功。残る既存の不具合は TASK-925 で扱う。実クリックで確かめたパス参照は 1 件のみ。#771 への返信は行っていない。
<!-- SECTION:FINAL_SUMMARY:END -->
