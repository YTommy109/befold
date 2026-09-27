---
id: TASK-641
title: FileListModel.onGitStatusChange の単一購読者の契約を doc コメントだけで守っている
status: Done
assignee:
  - '@claude'
created_date: '2026-09-27 06:23'
updated_date: '2026-09-27 07:03'
labels: []
dependencies:
  - TASK-638
references:
  - BefoldApp/befold/Viewer/FileListModel.swift
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/App/ViewerWindowAssembler.swift
priority: low
type: task
ordinal: 841000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-637（commit c1de117a）の責務レビュー L1 への対応として、`FileListModel.onGitStatusChange` の doc に「購読者は `SidebarTreePresenter` の 1 者（init で繋ぐ）。スロットは 1 つなので上書きしないこと」と書いて済ませた。`/code-review high` がこれを `.claude/CLAUDE.md`「決めたことには、破れたら落ちるものを付ける」に照らして指摘した。

## 現状（検証済み）

- `onGitStatusChange` は `@ObservationIgnored var` で外から自由に代入できる。代入箇所は `SidebarTreePresenter` の init の 1 箇所だけ。
- 同じモデルの `onPresentationTargetChange` は `ViewerWindowAssembler.wirePresentationTargetChange` が組み立て側で代入している前例があり、テスト（`FileListModelPreviewTargetTests`）も直接代入している。将来 `onGitStatusChange` を同じ流儀で組み立て側から代入すると presenter のクロージャが黙って置き換わり、git 更新時の展開が止まる。
- そのとき落ちるテストは無い。`SidebarNavigatorReviewExpansionTests` は `ViewerWindowAssembler` を通らずに組み立てている。
- 併せて `SidebarTreePresenter.swift` 先頭の型 doc「この型は `fileListModel` の `entries` / `entriesDirectory` だけを書く」「`entries` / `entriesDirectory` 以外は書かない」が、init でのクロージャ代入と `display` / `gitStatus` の読み取りで文字どおりには古くなっている。

## 方向

TASK-638 でクロージャは引数なしになる。その後で、構造で守る（presenter だけが繋げる形にする、または 2 回目の代入で assert する等）か、破れたら落ちるテストを置くかを選ぶ。型 doc は実態に合わせて直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `onGitStatusChange` が presenter 以外から上書きされた場合に、ビルドが通らないか、テストが落ちるか、実行時に assert で止まる（どれか 1 つを選び、選んだ理由を Notes に残す）
- [x] #2 `SidebarTreePresenter.swift` 先頭の型 doc が、クロージャの接続と `display` / `gitStatus` の読み取りを含む現状と一致している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileListModel.onGitStatusChange の willSet で「既に繋がっていたら assert」にする
2. presenter 経由で繋いだ後に上書きすると止まることを exit test で担保する
3. SidebarTreePresenter の型 doc を、クロージャの接続と display / gitStatus 等の読み取りを含む現状へ直す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 選んだのは実行時 assert(AC#1)。理由: (a) ビルドで止める形(presenter 専用の型を FileListModel へ渡す、private(set) + 接続メソッド等)は Viewer 層のモデルに App 層の型を持ち込むか、同じ型の中の別メソッドからは結局書けてしまう。(b) 型グループの行数が SidebarNavigator 425/425・FileListModel 400/400 で上限に張り付いており、接続メソッドを足す形(+8 行)は FileListModel を 406 行にして check-type-group-size に掛かった。willSet の assert は +2 行で収まる。
- assert は debug ビルドだけで効く。テストは debug で走るので、組み立て側(ViewerWindowAssembler)から上書きする変更を入れれば、窓を組み立てるどのテストでも止まる。
- SidebarNavigatorReviewExpansionTests.overwritingGitStatusSubscriberTraps を追加(Swift Testing の exit test / #expect(processExitsWith: .failure))。assert を一時的に無効化すると EXIT_SUCCESS で落ちることを確認済み。
- 検証: swift test 全 2002 件緑、swiftlint の main との差分ゼロ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileListModel.onGitStatusChange の 2 回目の代入を willSet の assert で止め、presenter 経由で繋いだ後の上書きがプロセスを止めることを exit test で担保した(assert を外すと落ちることを確認)。SidebarTreePresenter の型 doc を購読の接続と読み取りを含む現状へ直した。全 2002 件緑・swiftlint 差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
