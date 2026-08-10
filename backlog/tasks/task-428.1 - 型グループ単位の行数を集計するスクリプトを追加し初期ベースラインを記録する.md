---
id: TASK-428.1
title: 型グループ単位の行数を集計するスクリプトを追加し初期ベースラインを記録する
status: To Do
assignee: []
created_date: '2026-08-10 12:33'
labels: []
dependencies: []
parent_task_id: TASK-428
priority: high
type: chore
ordinal: 104100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
型グループ（`Foo.swift` + 同ディレクトリの `Foo+*.swift` の合算）を単位として行数を集計するスクリプトを追加し、その時点の実測値をベースラインファイルとしてリポジトリへコミットする。このサブタスクでは判定・ブロックは行わない。負債の総量を可視化し、以降のサブタスクが比較対象として使える固定点を作ることが成果物。

## なぜ型グループ単位か

`BefoldApp/.swiftlint.yml:13-15` の `file_length` はファイル単位なので、責務を分けずにファイルだけ割れば必ず通る。TASK-411 の Description が実例を記録している —「すでに +Capabilities / +Diff / +WindowHelpers の 3 拡張が存在するが、これは同じ行数上限を回避するために切られたものであり責務の分離にはなっていない」。合算で数えればこの逃げ道が塞がる。

グループ化の根拠になる命名規約は `.claude/CLAUDE.md` に既にある（「閾値を緩めるのではなく `Type+Feature.swift` の extension へ分割する」）。既存の実例: `SidebarNavigator` + `+History` / `+SelectionMemory` / `+Expansion` / `+FolderNavigation`、`MainMenuBuilder` + `+ViewMenu`、`ViewerWindowController` + `+Assembly` / `+DiffPresentation`。

## 決めること（実装者が判断し Implementation Notes に残す）

- **カウント方法**: 物理行数（`wc -l`）か、コメント・空行を除いた実質行数か。SwiftLint の `file_length` は既定でコメント・空行も数えるため、物理行数を採ると数値の意味が揃う。どちらを採ったかと理由を記録する。
- **閾値**: `file_length` の warning と同じ 400 を型グループにも適用するか、合算単位である点を踏まえて別の値にするか。ベースライン記録段階では判定しないが、次サブタスクが使う値をここで決める。
- **対象範囲**: プロダクトのみか、テストターゲット（`befoldTests/` ほか）も含めるか。`.swiftlint.yml` の `excluded` は `.build` と `befold/Resources` のみで、テストは `file_length` の対象になっている。同じ扱いに揃えるのが既定。
- **ベースラインファイルの置き場と形式**: 差分レビューで増減が読み取れる形にすること（1 グループ 1 行など）。
- **孤児の extension**: 本体 `Foo.swift` が存在せず `Foo+Bar.swift` だけがある場合の扱い。

## 参考

- 同種の自前チェックスクリプトの前例: `scripts/check-doc-symbols.sh`（`--self-test` を備え、pre-commit から呼ばれる）。self-test の作法はここに揃える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 型グループ単位の行数を集計して出力するスクリプトが追加されている
- [ ] #2 Foo.swift と同ディレクトリの Foo+Feature.swift が 1 グループとして合算される（既存の SidebarNavigator 系・ViewerWindowController 系で確認できる）
- [ ] #3 スクリプトが --self-test を備え、集計とグループ化が期待どおり動くことを引数なしで検証できる
- [ ] #4 実測値を記録したベースラインファイルがリポジトリにコミットされている
- [ ] #5 カウント方法・閾値・対象範囲・孤児 extension の扱いの決定が Implementation Notes に理由つきで記録されている
<!-- AC:END -->
