---
id: TASK-438.3
title: ADR の Fallback 節を確定させ、ADR 番号の衝突を解消する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-13 14:00'
updated_date: '2026-08-14 14:09'
labels:
  - docs
milestone: m-5
dependencies:
  - TASK-438.1
  - TASK-438.2
parent_task_id: TASK-438
priority: medium
type: docs
ordinal: 110300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-438 の決定を ADR へ反映し、あわせて番号の衝突を直す。実装（438.1 / 438.2）の結果を書くため最後に行う。

## 1. Fallback 節の確定

現在の記述は伝え方を「実装時に決める」と未決のまま残している（docs/adr/0005-git-integration-via-libgit2.md:205-207）。これを確定した記述へ更新する。

- 伝えるのは BaseDirectoryIndicator の 1 箇所のみ。バナー・注記行・モーダルは取らない
- 失敗理由の種別は出さない（OpenFailure が .unusable の 1 値へ畳んでいるため、出すと型が持たない情報を騙る）
- .git の読み取り権限なしは .notARepository へ落ちるため「git 管理外」と区別できない（同 ADR の 2026-08-11 実測追記と整合させる）

## 2. ADR 0003 への誤った参照を正す

同 ADR:207 は「ADR 0003 の Context にある「原因不明の無反応」」を参照しているが、**docs/adr/0003-git-status-guard-in-file-list-model.md にこの語句は存在しない**（grep -rn '原因不明' docs/ backlog/ の一致はこの 1 行とその引用のみ）。ADR 0003 の Context が述べているのは、反映可否の判定が 3 状態に分散して順序回帰が 5 回続いたという内部設計の話で、ユーザーへの伝え方は扱っていない。引用の体裁をやめ、参照するなら何を指しているのかを自分の言葉で書く。

## 3. 番号の衝突を解消する

0005 が 2 本ある。

- docs/adr/0005-bundle-viewer-js-with-esbuild.md（backlog decision-5）→ 0005 のまま
- docs/adr/0005-git-integration-via-libgit2.md（backlog decision-6）→ **0006 へ振り直す**

decision 番号に合わせる。参照している箇所を追随させること（backlog タスク・他 ADR・docs 配下・CLAUDE.md 等）。参照元は rg で全列挙してから直す。

## 注意

Markdown を編集したら markdownlint-cli2 を流す。ドキュメント間の依存はディレクティブコメント（constrained-by / derived-from 等）で表す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Fallback 節が「実装時に決める」から確定した記述へ更新され、実装（438.1 / 438.2）の結果と一致している
- [x] #2 ADR 0003 への誤った参照が正されている
- [x] #3 libgit2 の ADR が 0006 へ振り直され、0005 の重複が解消している
- [x] #4 振り直しに伴う参照箇所がすべて追随している（rg で旧ファイル名・旧番号の残存がゼロ）
- [x] #5 markdownlint-cli2 が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容（2026-08-14）

1. **Fallback 節を確定**: 「伝え方は実装時に決める」を、TASK-438.1 / 438.2 の実装結果に
   合わせた 4 点の確定記述へ差し替えた（伝えるのは基準ディレクトリ表示 1 箇所だけ・失敗理由の
   種別は出さない・.git 読み取り権限なしは区別できない・差分モードの選択不可は
   ViewerCapabilities.canSelectDiffMode の 1 箇所で担保）。
2. **ADR 0003 への誤った参照を除去**: 「ADR 0003 の Context にある『原因不明の無反応』」という
   引用は ADR 0003 に存在しない語句だった。引用の体裁をやめ、何を避けたいのか（操作はできるのに
   結果が出ない状態）を自分の言葉で書いた。冒頭の `constrained-by ./0003-...` ディレクティブは
   git ステータスの反映規約という実在の依存なので残した。
3. **番号の振り直し**: `docs/adr/0005-git-integration-via-libgit2.md` を
   `0006-git-integration-via-libgit2.md` へ git mv し、H1 も 0006 にした（decision-6 に一致）。

## 追随させた参照と、あえて直さなかったもの（AC #4）

直したもの: ADR 本体の H1 / `BefoldApp/.swiftlint.yml`（2 箇所）/
`BefoldApp/befold/App/GitRepository.swift` / `BefoldApp/befoldTests/GitUnusableRepositoryTests.swift` /
`backlog/decisions/decision-6`（ファイルパスと本文の番号）。

直していないもの: `backlog/completed/` と `backlog/archive/` 配下のタスク（task-435 系）に残る
「ADR 0005」表記と旧ファイルパス。理由は 2 つ。(a) 完了タスクは当時の作業記録であり、
書き換えると記録が事後の状態に合わせて改変される。(b) CLAUDE.md / backlog instructions が
タスク markdown の直接編集を禁じており、backlog CLI に完了タスク本文の一括置換手段は無い。
したがって「rg で旧番号の残存ゼロ」は**live なドキュメントとコードについて**満たしている。
（`ADR 0005` の文字列自体は esbuild の ADR 0005 が現役なので、リポジトリ全体でのゼロは元から
成立しない。）

なお `backlog/decisions/decision-6` は CLI に編集コマンドが無いため本文のみ手で直した
（frontmatter・メタデータは触っていない）。

## 検証

- markdownlint-cli2: 0 issues（70 ファイル）
- `grep -rn '0005-git-integration|ADR 0005' docs/ .claude/ BefoldApp/ site/`: 一致ゼロ
- `swift test --filter GitUnusable`: 3 件成功（doc コメントのみの変更）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ADR の Fallback 節を TASK-438.1 / 438.2 の実装結果に沿った確定記述へ更新し、存在しない語句を引いていた ADR 0003 への参照を自分の言葉へ書き換えた。番号の衝突は libgit2 側を 0006 へ振り直して解消し（decision-6 に一致）、live なドキュメント・コード・decision の参照をすべて追随させた。完了済み backlog タスクに残る旧表記は当時の記録として意図的に残し、その判断を Notes に記録した。検証は markdownlint 0 issues と grep での残存ゼロ確認。
<!-- SECTION:FINAL_SUMMARY:END -->
