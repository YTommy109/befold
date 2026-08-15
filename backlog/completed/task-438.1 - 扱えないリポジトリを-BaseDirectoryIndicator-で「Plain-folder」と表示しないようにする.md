---
id: TASK-438.1
title: 扱えないリポジトリを BaseDirectoryIndicator で「Plain folder」と表示しないようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-13 13:59'
updated_date: '2026-08-14 13:47'
labels:
  - ux
  - git
milestone: m-5
dependencies: []
parent_task_id: TASK-438
priority: medium
type: bug
ordinal: 110100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-438 の決定（論点 1: 区別する。ただし BaseDirectoryIndicator の 1 箇所のみ）の実装。

## 現状の問題

BaseDirectoryIndicator.swift:12,26-27 はアイコンとツールチップを kind == .gitRoot の二値で決めている。kind は SidebarBaseDirectoryResolver.swift:48 の repositoryRoot(forDirectoryAt:) -> URL? 由来で、libgit2 が開けないリポジトリ（partial clone / reftable / 未知の extensions.*）はここが nil になる。結果、**git リポジトリなのに folder アイコン + 「Plain folder」と表示される**。これは静かな縮退ではなく事実と異なる表示。

BaseDirectoryIndicator は FeatureGate 配下ではないため stable のユーザーに見える。ADR の縮退 3 点のうちサイドバーのバッジ（FeatureGate.isSidebarGitStatusEnabled）と差分（isSourceDiffEnabled）は dev 限定なので、stable での実害はこの 1 箇所に集中している。

## 方針

- 表示を 3 状態にする。git ルート / ただのフォルダ / **git リポジトリだが扱えない**
- 扱えない場合のアイコンは arrow.triangle.branch のままにし、ツールチップで「befold では扱えないため git 機能は無効」であることを伝える
- **バナー・注記行は足さない。モーダルも取らない**（ADR の「静かに落とす」方針は維持する）
- **失敗理由の種別は出さない**。GitLibrary.OpenFailure（GitLibrary.swift:30-38）は partial clone / reftable / 未知拡張を .unusable の 1 値へ意図的に畳んでおり（エラーメッセージは版差のため見ない = GitLibrary.swift:116-117）、理由別の文言は型が持たない情報を騙ることになる

## 配線

新しい状態は増やさない。GitRootLookup（GitRepository.swift:7-17）は既に .root / .notARepository / .undetermined を区別しており、SidebarGitReading.repositoryRoot(forDirectoryAt:) -> URL?（SidebarGitReading.swift:26）が URL? へ潰す時点で情報が捨てられている。**捨てている情報を UI まで通すだけ**。戻り型の変更が起点になる。

Localizable.xcstrings へキーを追加する際は、キー順にソートし直さず近縁キー（sidebar.baseDirectory.*）の直後に挿入すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 libgit2 が開けないリポジトリを開いたとき、BaseDirectoryIndicator が「Plain folder」と表示しない
- [x] #2 その状態で git リポジトリではあるが befold では扱えないことがツールチップから分かる
- [x] #3 失敗理由の種別（partial clone / reftable / 未知拡張）を文言に出していない
- [x] #4 git ルート / ただのフォルダ / 扱えないリポジトリの 3 状態が、扱えないリポジトリのフィクスチャを使ったテストで固定されている（GitUnusableRepositoryTests のフィクスチャが流用できる）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitRootLookup を befold/App/GitRepository.swift から BefoldKit へ移し public にする（BaseDirectoryDescriptor が BefoldKit にあるため）
2. GitFileIndexing に repositoryRootLookup(forFileAt:) -> GitRootLookup を追加。既定は repositoryRoot(forFileAt:) から .root/.notARepository へ写す（git を扱わないシームは従来どおり）。GitCommandFileIndex だけが .undetermined を返せるよう override
3. SidebarGitReading.repositoryRoot(forDirectoryAt:) -> URL? を repositoryRootLookup(forDirectoryAt:) -> GitRootLookup へ変える（URL? へ潰す時点で情報が消えているため戻り型の変更が起点）
4. BaseDirectoryDescriptor.Kind に unusableRepository を追加し init(rootLookup:workspaceRoot:) を足す。基準ディレクトリ自体は gitRoot ?? workspaceRoot 規則のまま（PathRelativizer との一致を崩さない）。kind は表示だけに効く
5. BaseDirectoryIndicator を switch による 3 分岐にする（Kind に case が増えたらコンパイルエラーになる形にし、== .gitRoot の二値判定をやめる）。アイコンは扱えないリポジトリでも arrow.triangle.branch
6. Localizable.xcstrings に sidebar.baseDirectory.unusableRepository を sidebar.baseDirectory.* の近縁位置へ挿入（ソートし直さない）
7. テスト: (a) BaseDirectoryDescriptor の 3 状態、(b) 扱えないリポジトリのフィクスチャ（GitLibraryTests.makeUnopenableRepository）で GitCommandFileIndex→SidebarGitReader→Resolver が unusableRepository を返す、(c) BaseDirectoryIndicator のツールチップが Plain folder ではないこと
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-14）

情報を捨てる位置を UI の手前まで下げただけで、新しい状態は増やしていない。

- `GitRootLookup` を befold/App から BefoldKit へ移動（`BaseDirectoryDescriptor` が BefoldKit にあるため）
- `GitFileIndexing.repositoryRootLookup(forFileAt:)` を追加。既定は `repositoryRoot` から写すため、git を扱わないシームは従来どおり 2 値。`.undetermined` を返せるのは上書きした `GitCommandFileIndex` だけ
- `SidebarGitReading.repositoryRoot(forDirectoryAt:) -> URL?` を `repositoryRootLookup(forDirectoryAt:) -> GitRootLookup` へ変更（潰していた情報を運ぶ）
- `BaseDirectoryDescriptor.Kind.unusableRepository` を追加。**基準ディレクトリ自体は `gitRoot ?? workspaceRoot` 規則のままで、検出結果が効くのは種別（表示）だけ**（PathRelativizer との一致を崩さない）
- `BaseDirectoryIndicator` を `== .gitRoot` の二値判定から `switch` の 3 分岐へ。Kind に case が増えたらコンパイルエラーになる形にした（今回の不具合はまさに「増えた状態が黙って git ではない側へ倒れる」形だった）

## 検証

- `swift test`: 1519 tests / 241 suites すべて成功
- 修正を戻して落ちることを確認: `BaseDirectoryDescriptor(rootLookup:)` の `.undetermined` を `.plainFolder` へ戻すと 21 行の失敗が出る
- swiftlint ベースライン差分: 真の新規ゼロ / 解消ゼロ（main 54 件・作業ツリー 54 件）
- markdownlint-cli2: 0 issues

## docs 追随

`docs/dev/native-app-design.md` のコンポーネント一覧へ `BaseDirectoryDescriptor` / `BaseDirectoryIndicator` の行を追加し、3 種別と「失敗理由は出さない」ことを記した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
libgit2 が開けないリポジトリを「Plain folder」と表示していた事実誤認を、GitRootLookup を UI の手前まで運ぶことで解消した。BaseDirectoryDescriptor.Kind に unusableRepository を足し、BaseDirectoryIndicator を switch の 3 分岐にしてアイコンは git のまま・ツールチップで git 機能が無効であることだけを伝える（失敗理由の種別は出さない）。検証は swift test 1519 件成功、扱えないリポジトリの実フィクスチャを通したテスト（GitUnusableRepositoryTests / BaseDirectoryIndicatorTests / SidebarNavigatorBaseDirectoryTests）、修正を戻すと 21 行失敗することの確認、swiftlint 新規ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
