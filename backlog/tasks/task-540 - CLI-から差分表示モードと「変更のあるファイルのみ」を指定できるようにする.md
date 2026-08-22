---
id: TASK-540
title: CLI から差分表示モードと「変更のあるファイルのみ」を指定できるようにする
status: To Do
assignee: []
created_date: '2026-08-22 14:50'
updated_date: '2026-08-22 14:51'
labels: []
milestone: m-10
dependencies:
  - TASK-537
priority: medium
ordinal: 790000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`befold` CLI で、差分表示モードと、サイドバーの『変更のあるファイルのみ』を指定して開けるようにする。

## なぜ要るか

コーディングエージェントに書かせた変更を人がレビューする往復（TASK-539 の題材）では、**開いた瞬間に差分が出ていて、変更のあったファイルだけが並んでいる**のが望ましい。今は開いてから毎回 2 操作している。`befold-review` スキルのようにエージェント側から開く経路では、その 2 操作を人に強いることになる。

## 現状（実測）

既存の表示オプションは `BefoldApp/BefoldCLI/OpenCLIOptions.swift` にある。`--hidden-files/--no-hidden-files` `--line-numbers/--no-line-numbers` `--source/--preview` `--sidebar/--no-sidebar` `--sort` の 5 種で、**両立しないペアは `EnumerableFlag` の単一値 `@Flag` として宣言し、同時指定をパース段階で構造的に弾いている**（同ファイル 97 行付近のコメント）。未指定は nil で「保存済み設定を維持」を表す 3 値意味論。

## 設計上の要点

### 1. `--diff` は `--source/--preview` と同じ 1 つの enum に入れる

`SourceModeFlag` は `.source` / `.preview` の 2 値で、受け渡しは `CLIOpenOptions.sourceMode: Bool?`（`BefoldApp/BefoldCLI/CLIOpenOptions.swift:15`）。一方 `ViewerDisplayMode` は rendered / source / diff の **3 値**なので、**Bool では表現できない**。

`--diff` を別の `@Flag` として足すと `--source --diff` の同時指定が通ってしまい、既存の『構造的排他』が崩れる。`SourceModeFlag` を 3 値へ広げ、`sourceMode: Bool?` を表示モードの enum へ置き換えるのが筋。**これは値の持ち方を変える変更なので、着手前に `/review-design` を 1 回回す。**

消費側は `ViewerDisplayOptionsApplier.swift:26` の `controller.applyCLIDisplayMode(isSourceMode:)` と、新規ウィンドウ側の `ViewerWindowController.swift:265` の `sourceModeOverride`。両方が Bool を前提にしているので揃えて変える。

### 2. `--diff` が通らない場合の縮退を決める

差分表示を選べるかは git 側の事実に依存する（`GitDiffAvailability`）。`.unavailable`（git 管理外）や `.unchanged`（変更なし）では `canSelectDiffMode` が false になる。CLI で `--diff` を指定してこれらに当たったとき、**黙って通常表示になるのか、CLI がエラーを返すのか**を決める。可用性は非同期に届くため、CLI の応答時点では未確定（`.undetermined`）であることにも注意。

### 3. `--changed-files-only` は TASK-537 と重なる

サイドバーの絞り込みは `FileListModel.showChangedFilesOnly`。git 管理外では効かないが、現状は操作できてしまう（TASK-537）。**CLI から指定できるようにすると、この穴が『指定したのに何も起きない』という形でも現れる。** TASK-537 の判定（開いているフォルダが git 管理下か）を先に入れ、CLI 側もそこを参照する。

## 忘れずに揃えるもの

- `README.md` と `README.ja.md` に CLI オプション表がある（実測: `grep -rln 'no-hidden-files'` で両方に一致）
- 既存オプションと同じく、**この起動限りの窓単位の上書き**とし、保存された既定値は書き換えない（`ViewerDisplayOptionsApplier` のコメントに方針あり）
- パス引数なしの指定が既存インスタンスへ届くこと（過去に TASK-82 / TASK-73.11 / TASK-413 で 3 回壊れている経路）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold --diff でファイルを差分表示モードで開ける
- [ ] #2 befold --changed-files-only で、変更のあるファイルだけが並んだ状態で開ける
- [ ] #3 --source / --preview / --diff の同時指定がパース段階で弾かれる
- [ ] #4 git 管理外・変更なしのファイルに --diff を指定したときの振る舞いを決め、テストで固定してある
- [ ] #5 パス引数なしでの指定が、既に開いているウィンドウにも適用される
- [ ] #6 README.md と README.ja.md のオプション表に追記してある
- [ ] #7 着手前に /review-design を回し、結果を Implementation Plan に反映してある
<!-- AC:END -->
