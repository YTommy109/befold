---
id: TASK-459
title: ViewerWindowManager（型グループ 610 行）を独立型へ切り出して閾値以下に戻す
status: Done
assignee: []
created_date: '2026-08-12 02:21'
updated_date: '2026-08-12 03:07'
labels: []
dependencies: []
priority: low
ordinal: 683000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-426 で ViewerWindowManager を分割したが、切り出し先を同ディレクトリの ViewerWindowManager+*.swift にしたため、型グループ（Foo.swift + 同ディレクトリの Foo+*.swift の合算）としては 610 行で閾値 400 を超えたままになっている。scripts/type-group-baseline.txt に凍結値として残っており、TASK-428.5（ベースライン撤去）の着手を妨げている。

内訳（実測 2026-08-12）:
ViewerWindowManager.swift 155 / +OpenViewer 144 / +SessionSync 93 / +GlobalDisplay 82 / +TabGroups 69 / +RecentRepositories 67。

extension への分割では型グループの合計は減らないため、責務を独立した型へ移す（同ディレクトリの ViewerWindowManager+*.swift ではなく、別の型として切り出す）。どの責務を独立型にするかは着手時に判断する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 型グループ BefoldApp/befold/App/ViewerWindowManager の行数が 400 以下になっている（scripts/check-type-group-size.sh の出力で確認）
- [x] #2 scripts/type-group-baseline.txt から ViewerWindowManager のエントリが削除されている
- [x] #3 swift test が緑で、swiftlint のベースライン差分がゼロである
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerTabGrouping（@MainActor enum・static のみ）を新設し、+TabGroups.swift 全体と +SessionSync の viewerPath(of:) を移す。rescueWindowsDetachedFromSpace は windows を引数で受ける形へ。呼び出し元（SessionRestorer 4 箇所・AppDelegate:126）を新型へ向け直す。→ 536 行
2. ViewerDisplayOptionsApplier（@MainActor enum・static）を新設し、+OpenViewer の reopenExistingWindow を移す。前面化（NSApp.activate / focusWindow）は openViewer 側に残す。→ 508 行
3. GlobalDisplayBroadcaster（@MainActor final class）を新設し、+GlobalDisplay.swift を丸ごと移す。sidebarDisplayPreference / bookmarkStore / controllers 供給クロージャ（weak self）を保持。呼び出し元は windowManager.display.* へ向け直す。→ 434 行
4. RecentRepositoryRecorder（@MainActor final class）を新設し、+RecentRepositories.swift と専用 4 依存（recentRepositoriesStore / repositoryIdentityResolver / onRepositoryRecorded）を移す。gitFileIndex は AppDelegate が読むため VWM にも残し同一インスタンスを共有。recordAllRecentRepositoryTabGroups だけ forwarder を残す（allControllers の走査を外へ漏らさないため）。→ 359 行
5. 仕上げ: ViewerWindowManager.swift の型 doc 更新、docs/dev/native-app-design.md へ 4 型を追記、xcodegen generate、--update-baseline。

不変条件: controllers 辞書と register/detach は VWM に据え置き（新型は値または読み取り専用クロージャしか受けない）。新型の init に共有依存の既定値を書かない（TASK-319 の規則）。ADR 0002 の「窓ごとのライブ値を配ってはならない」は GlobalDisplayBroadcaster の型 doc へ格上げする。

## /review-design の反映（2026-08-12）

- 【変更】RecentRepositoryRecorder は AppDelegate ではなく ViewerWindowManager.init 内で組み立てる。理由: gitFileIndex は init にデフォルト引数（GitCommandFileIndex()）を持つため、recorder を外で組み立てる形にすると別インスタンスを渡す書き方が可能になり、共有索引の二重化がコンパイルエラーにならない（TASK-319 と同型）。manager 内で自身の stored property から組み立てれば破りようがない。副次的に AppDelegate / MockedViewerWindowManager / テスト fixture の変更がゼロになる。代償として見積もりは 359 → 約 375 行（余裕 25 行）。
- 【追加】新型（broadcaster / recorder）は gitStatusStore を保持しない。AppDelegate.swift:95 が init 後に差し替える var のため、init 時に値で捕まえると既定の無効 store を掴んだままになる。理由を型 doc へ明記する。
- 【追加】refreshAllSidebars / refreshAllToolbars の doc「呼んでよいのはこの型と その extension だけ」は移設後に事実と食い違うため、新しい境界（一括反映は broadcaster を通す / 窓 1 つへの再同期は controller の API を直接呼ぶ）へ書き直す。
- 【確認済み】移動対象 5 ファイルに FeatureGate 参照は無く、唯一の参照 makeDiffLoader() は ViewerWindowManager.swift に残る。BefoldApp/.swiftlint.yml:68 の allowlist と FeatureGate.swift:25 の doc はどちらも更新不要。
- 【スコープ外】recordRecentRepositoryIfNeeded の detached タスクは着地時に controller の生存だけを見てリポジトリルートを書くため、解決中にファイル切替が起きると切替前のリポジトリへ記録されうる（項目 8 の一致確認欠落）。既存挙動のため別タスクとして起票する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実測（2026-08-12）

型グループ BefoldApp/befold/App/ViewerWindowManager: **610 → 368 行**（scripts/check-type-group-size.sh）。段階ごとの実測は 610 → 535 → 507 → 435 → 368。

切り出した 4 型（いずれも同ディレクトリの独立した型グループ）:

| 型 | 行 | 責務 |
|---|---|---|
| ViewerTabGrouping | 79 | タブグループ規則（結合・スナップショット組み立て・Space 救出）。viewerPath(of:) も移し、manager の状態に依存しない static のみになった |
| ViewerDisplayOptionsApplier | 43 | 既存ウィンドウへの CLI 表示オプション適用。前面化は openViewer 側に残す |
| GlobalDisplayBroadcaster | 111 | アプリ全体の表示設定の一括反映。ViewerDisplayMode / ZoomStore / GitStatusStore を持たない形で ADR 0002 と差し替え順序を担保 |
| RecentRepositoryRecorder | 96 | 「最近使ったリポジトリ」の記録。ViewerWindowManager.init が自身の gitFileIndex から組み立てるため、別の索引を掴む書き方ができない |

呼び出し元は forwarder を残さず新型へ向け直した（AppDelegate / AppDelegate+HostedPanels / DocumentOpener / SessionRestorer / テスト 3 ファイル）。例外は recordAllRecentRepositoryTabGroups の 1 つだけで、allControllers の組み立てを呼び出し元へ漏らさないため委譲で残した。

検証:
- swift test 全実行 1446 tests / 227 suites 緑（Integration 含む）
- swiftlint: 分岐ベース（HEAD=93df5a9）と比較して差分ゼロ（56 件 → 56 件、正規化後の集合が一致）
- scripts/check-type-group-size.sh --check 緑。ベースラインから ViewerWindowManager の行が消え、残りは ViewerWindowController(802) / ViewerStore(531) の 2 件
- markdownlint-cli2 0 issues

新規テスト:
- ViewerTabGroupingTests（移設 4 件 + 結合先 nil の縮退 1 件）。bare NSWindow は isReleasedWhenClosed の既定 true が ARC 下の close() で過剰解放になり SIGSEGV になるため false を明示している
- ViewerDisplayOptionsApplierTests 2 件（並び順の指定なし判定 / サイドバー開閉の優先順位）
- ViewerWindowManagerRecentRepositoriesTests に worktree の mainRoot 記録規約を 1 件追加（従来 fixture は mainRoot == root 固定で片方向しか見ていなかった）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowManager の型グループを 610 → 368 行にした。extension では合算値が減らないため、責務を 4 つの独立型（ViewerTabGrouping / ViewerDisplayOptionsApplier / GlobalDisplayBroadcaster / RecentRepositoryRecorder）へ切り出し、呼び出し元は原則として新型へ向け直した。controllers 辞書と register/detach は manager に据え置き、新型は値または読み取り専用クロージャしか受け取らない。共有依存の単一性は「渡す余地を無くす」形（recorder は manager の init が自身の gitFileIndex から組み立て、broadcaster は lazy var で自身の preference を渡す）で構造的に担保した。swift test 1446 件緑、swiftlint 差分ゼロ、型グループ判定緑、ベースラインから当該エントリを削除。
<!-- SECTION:FINAL_SUMMARY:END -->
