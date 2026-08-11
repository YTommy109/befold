---
id: TASK-428.1
title: 型グループ単位の行数を集計するスクリプトを追加し初期ベースラインを記録する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 12:33'
updated_date: '2026-08-11 04:47'
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
- [x] #1 型グループ単位の行数を集計して出力するスクリプトが追加されている
- [x] #2 Foo.swift と同ディレクトリの Foo+Feature.swift が 1 グループとして合算される（既存の SidebarNavigator 系・ViewerWindowController 系で確認できる）
- [x] #3 スクリプトが --self-test を備え、集計とグループ化が期待どおり動くことを引数なしで検証できる
- [x] #4 実測値を記録したベースラインファイルがリポジトリにコミットされている
- [x] #5 カウント方法・閾値・対象範囲・孤児 extension の扱いの決定が Implementation Notes に理由つきで記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 型グループ（dir + 型名）で行数を合算する集計スクリプトを追加する
2. --self-test で合算・ディレクトリ分離・孤児 extension・excluded 除外を検証する
3. 実測して閾値超過グループをベースラインファイルへ凍結する
4. 決定事項（カウント方法・閾値・対象範囲・孤児 extension・ベースラインの粒度）を Notes へ記録する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決定事項（TASK-428.1）

- **カウント方法: 物理行数（wc -l）**。SwiftLint の file_length は既定でコメント・空行も数えるため、物理行数を採ると閾値 400 の意味が両者で揃う。実質行数にすると「file_length は 401 で鳴るがグループ集計は 380」のような食い違いが出る。
- **閾値: 400（file_length warning と同値）**。合算単位なので緩めたくなるが、「400 行の型は分割を検討する」という基準自体はグループでも変わらないため揃えた。環境変数 TYPE_GROUP_THRESHOLD で上書きできる（self-test 用）。
- **対象範囲: BefoldApp 配下の全 .swift。除外は .swiftlint.yml の excluded と同じ .build / befold/Resources の 2 つのみ**。テストターゲットも file_length の対象なので同じ扱いに揃えた（実際 ViewerWindowControllerTests 585 行などが超過している）。
- **孤児 extension（本体 Foo.swift が無く Foo+Bar.swift だけ）も Foo グループとして数える**。本体の有無で扱いを変えると「本体を消してから extension を増やす」逃げ道が残るため。実例: URL+NormalizedPathKey / NSMenu+Items / CLIOpenOptions+ViewerSortOrder。
- **ベースラインに記録するのは閾値超過グループのみ（12 件）**。全 382 グループを凍結すると通常の 1 行追加でも検知されて形骸化する。閾値以下のグループは「新規に閾値を超えたら検知」という素朴な判定で足り、これは TASK-428.5 でベースラインを撤去したときに残る判定と同じ形なので、最終形への移行が「ファイルを消すだけ」になる。
- **ベースラインの並び順はキーの辞書順**。行数順にすると 1 グループの増減で無関係な行が動き、差分レビューで増減が読めなくなる。

## 実測（初期ベースライン）

全 382 グループ中、400 行超は 12 件。ファイル単位の起票時実測（7 件）に対し 5 件増えており、うち上位 2 件は extension 分割で数値上は隠れていたもの:

- ViewerRenderer 1300（BefoldRenderKit、5 本の extension）
- ViewerWindowController 1255（TASK-411 で 978 行から分割済みだが合算では増えている）
- SidebarNavigator 611 / FileListModel 459 / FileListView 437 が新たに顕在化

file_length の error 閾値 1000 にファイル単位では触れないが、グループ合算では上位 2 件が 1000 行を超えている。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
型グループ（Foo.swift + 同ディレクトリの Foo+*.swift）単位で行数を合算する scripts/check-type-group-size.sh を追加し、初期ベースラインを scripts/type-group-baseline.txt へ凍結した。

検証: --self-test が合算・ディレクトリ違いの分離・孤児 extension・excluded 除外の 4 点を一時ツリーで確認して OK。実データでも ViewerWindowController = 1255（本体 263 + extension 10 本、wc -l の合計と一致）、SidebarNavigator = 611（本体 364 + extension 4 本）、ViewerWindowControllerDelegate は別グループとして分離されることを wc -l と突き合わせて確認した。

実測: 全 382 グループ中 400 行超は 12 件。ファイル単位の起票時実測 7 件に対し、extension 分割で隠れていた ViewerRenderer 1300 / ViewerWindowController 1255 ほか 5 件が新たに顕在化した。
<!-- SECTION:FINAL_SUMMARY:END -->
