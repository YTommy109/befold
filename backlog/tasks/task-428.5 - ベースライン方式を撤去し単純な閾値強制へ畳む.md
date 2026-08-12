---
id: TASK-428.5
title: ベースライン方式を撤去し単純な閾値強制へ畳む
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-10 12:35'
updated_date: '2026-08-12 03:33'
labels: []
dependencies:
  - TASK-459
  - TASK-460
parent_task_id: TASK-428
priority: low
type: chore
ordinal: 104500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ベースライン（ラチェット）は負債返済期間中の足場であり、恒久的な仕組みではない。全ての型グループが閾値以下になった時点でベースラインファイルと差分比較のロジックを撤去し、「型グループの行数が閾値以下であること」だけを見る単純な判定へ畳む。

畳む理由は、ベースラインが残っている限り「ベースラインを上げれば通る」という逃げ道が残るため。差分レビューで見えるので抑止は効くが、逃げ道が構造として存在しない状態のほうが強い。`.claude/CLAUDE.md` の「破りようのない構造へ変える」に沿う。

## 前提（着手条件）

依存タスクが全て完了し、ベースラインファイルの中身が空（またはすべて閾値以下）になっていること。着手時にベースラインの実際の中身を確認し、残っているエントリがあればその分の返済タスクが起票されているかを確かめる。

## 併せて行うこと

撤去後は `docs/dev/rules/product-code.md` の責務分離節へ、型グループ単位の閾値が機械的に強制されている旨を追記する（現状この節は「閾値は上限であって目標ではない」という運用規定のみで、強制機構への言及が無い）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ベースラインファイル（増加のみ禁止のラチェット）が撤去されている
- [x] #2 判定が「型グループの行数が閾値以下か、または明示された恒久例外に該当するか」のみになり、差分比較のロジックが残っていない
- [x] #3 恒久例外は「グループキー・上限行数・理由」を持つ形で列挙されており、理由の記載が無いエントリを追加できない（スクリプトが弾く）
- [x] #4 ViewerWindowController が恒久例外として上限 900 行・理由付きで登録されている
- [ ] #5 main で CI が緑である
- [x] #6 docs/dev/rules/product-code.md の責務分離節に、型グループ単位の閾値が機械強制されている旨と恒久例外の運用が追記されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## ベースライン撤去の設計を「閾値 + 恒久例外」へ変更した（2026-08-11）

起票時の AC は「ベースラインが空になる → 単純な閾値強制へ畳む」を前提にしていたが、依存タスクを全て完了してもベースラインは空にならないことが確定した。

**実測**: `scripts/type-group-baseline.txt` に `852  BefoldApp/befold/App/ViewerWindowController` が残っている。その返済タスク TASK-441 は Done で、AC #1 は「400 行は init の Parameter doc 約 120 行と移動不能な @objc アクション 13 個 + validate 対応表が支配的で到達不能」とユーザー確認のうえ 900 行へ書き換え済み。`backlog search "ViewerWindowController"` で 852 → 400 を目指す To Do タスクは存在しない。

このままでは着手条件（ベースラインが空）が永久に満たされず、親 TASK-428 の AC #4 も閉じない。

**決定（ユーザー判断, 2026-08-11）**: 追加の分割タスクは起票せず、ViewerWindowController を**恒久例外として明文化**する。撤去するのは「増加のみ禁止のラチェット（ベースライン差分比較）」であって、例外そのものではない。両者の違い:

- ベースライン: 現状値の凍結。全グループが対象で、値を書き換えれば通るため逃げ道が残る
- 恒久例外: グループキー・上限行数・**理由**の 3 点セットで明示的に列挙する。理由の無いエントリは弾く。追加はレビューで必ず目に付く

これにより「ベースラインを上げれば通る」という逃げ道は消え、例外は「なぜ 400 に収まらないか」を書かないと登録できない形になる。

## 着手条件の再確認（2026-08-12）

依存 10 件は全て Done だが、`scripts/check-type-group-size.sh` の実測でベースラインは空になっていない。残存 3 件:

- 802 `befold/App/ViewerWindowController` — 恒久例外（上限 900・理由付き）として登録する方針が確定済み（AC #4）
- 610 `befold/App/ViewerWindowManager` — 未決だった
- 531 `befold/Viewer/ViewerStore` — 未決だった

TASK-426 / TASK-430 は Done だが、切り出し先を同ディレクトリの `Foo+*.swift` にしたため型グループ合計は減っていない（このチェックは `Foo.swift` と同ディレクトリの `Foo+*.swift` を合算する）。

**決定（ユーザー判断, 2026-08-12）**: 恒久例外を増やさず、返済タスクを起票してから着手する。TASK-459（ViewerWindowManager）/ TASK-460（ViewerStore）を起票し、本タスクの依存に追加した。恒久例外は ViewerWindowController の 1 件のみとする。

## 撤去の実装（2026-08-12）

ベースライン方式（`scripts/type-group-baseline.txt` と差分比較）を撤去し、判定を
「型グループの行数が閾値 400 以下、または `scripts/type-group-exceptions.txt` の恒久例外の上限以下」だけに畳んだ。

- 例外の形式は `<グループキー><TAB><上限行数><TAB><理由>` の 3 列。列数不足・上限が非数値・理由が空白のみのエントリは形式不正として exit 1 で弾く（self-test の「理由なしの例外」ケースで担保）
- 登録は `BefoldApp/befold/App/ViewerWindowController`（上限 900・理由付き）の 1 件のみ。実測 802 行
- 終了コード: 0 = 問題なし / 1 = 閾値超過・例外の上限超過・形式不正 / 2 = 不要な例外が残っている（返済済みグループの例外行、または集計結果に無いキー）。2 は CI で `::warning::` に留める（返済した側を赤くしないため）
- `--baseline` / `--update-baseline` オプションは削除。「値を書き換えれば通る」逃げ道が構造として消えた
- self-test を 5 ケースへ差し替え: 閾値超過 / 例外で許容 / 例外の上限超過 / 理由なしの例外 / 不要な例外（閾値以下・消滅の 2 種）
- 配線の追随: ci.yml の `on.paths` と changes ジョブの grep（baseline → exceptions）、type-group-size ジョブの警告文、warn-type-group-growth.sh の doc

**実測**: `scripts/check-type-group-size.sh --self-test` OK、`--check` exit 0（「型グループの行数は閾値以内です」）、`markdownlint-cli2` 0 issues。Swift コードの変更は無いためビルド・テストは対象外。

AC #5（main で CI が緑）はマージ後に確認する。
<!-- SECTION:NOTES:END -->
