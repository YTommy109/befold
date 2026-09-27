---
id: TASK-641
title: FileListModel.onGitStatusChange の単一購読者の契約を doc コメントだけで守っている
status: To Do
assignee: []
created_date: '2026-09-27 06:23'
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
- [ ] #1 `onGitStatusChange` が presenter 以外から上書きされた場合に、ビルドが通らないか、テストが落ちるか、実行時に assert で止まる（どれか 1 つを選び、選んだ理由を Notes に残す）
- [ ] #2 `SidebarTreePresenter.swift` 先頭の型 doc が、クロージャの接続と `display` / `gitStatus` の読み取りを含む現状と一致している
<!-- AC:END -->
