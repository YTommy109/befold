---
id: TASK-187
title: FeatureGate 機構を撤去し、ゲート配下の 3 機能を常時有効化する
status: To Do
assignee: []
created_date: '2026-07-28 14:23'
updated_date: '2026-08-13 14:15'
labels:
  - refactor
dependencies:
  - TASK-186
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-git-status-design.md
priority: high
type: chore
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold は stable リリースを行わず dev リリースのみを配布する方針のため、FeatureGate による「stable では露出しない」場合分けは価値を生まず、コード・テスト・規約の三重の維持コストだけが残っている。本タスクは機構ごと撤去し、ゲート配下の 3 機能を常時有効化する。

これは stable 昇格（起票時の目的）ではなく、分岐除去によるコスト削減が目的である。起票時の Description にあった「TASK-186 が dogfood され安定したら」「libgit2 移行（TASK-435）の後で」という前提はいずれも本タスクの判断材料ではなくなった（TASK-435 は 2026-08-10 に Done）。

## 撤去対象（2026-08-13 実測）

- `BefoldApp/befold/App/FeatureGate.swift` — 型ごと削除。3 プロパティ（isSidebarGitStatusEnabled / isSourceDiffEnabled / isSidebarTreeEnabled）、inProgressFeaturesEnabled、純粋判定関数。
- `FeatureGate.` を参照するプロダクトファイル 7 件 — ViewerWindowManager / ViewerWindowAssembler / MainMenuBuilder / MainMenuBuilder+ViewMenu / SidebarDisplayPreference / PerFileStateStore / ModeSegments。
- ゲート値を下位へ渡す引数ラベル（出現数は宣言・呼び出し・テストの合計）— isSourceDiffEnabled 73、isChangedFilesOnlyAvailable 48、isTreeLayoutAvailable 47、isGitStatusAvailable 8。引数そのものを消して常時有効の経路 1 本にする。
- `BefoldApp/.swiftlint.yml` の custom rule `feature_gate_direct_reference` と対応する excluded 一覧。
- `BefoldApp/befoldTests/FeatureGateTests.swift` / `FeatureGateEnumerationTests.swift`。ゲート値を引数で受ける形を検証していた他テスト（ViewerWindowControllerSourceModeTests / ViewerWindowControllerToolbarTests / MainMenuBuilderTests / LocalizationTests）は、ゲート引数を外した呼び出しへ書き換える。
- `.claude/CLAUDE.md` の「フィーチャーゲート」節、およびコミット規約の `(gate)` スコープ規定。`/release-notes stable` が `(gate)` を除外する仕組みも不要になる。

## 判断が要る点

`AppVersion.isPrerelease` の本番利用者は FeatureGate.swift:83 だけで、撤去すると本番未使用になる（残りは AppVersionTests のみ）。AppVersion は BefoldCLI の public API であり、削除ではなく残す方針を取るなら、その判断を Implementation Notes に記録する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FeatureGate.swift が削除され、リポジトリ内のプロダクトコードに FeatureGate への参照が 0 件である（rg 'FeatureGate' で BefoldApp 配下のヒットが 0）
- [ ] #2 3 機能（サイドバー git ステータス / ソース表示の git 差分 / サイドバーのツリー展開）が、ビルド構成やバージョン文字列によらず常時有効である
- [ ] #3 ゲート値を下位へ渡していた引数（isSourceDiffEnabled / isChangedFilesOnlyAvailable / isTreeLayoutAvailable / isGitStatusAvailable）が宣言ごと撤去され、デフォルト引数による復活余地も残っていない
- [ ] #4 SidebarDisplayPreference と PerFileStateStore の「無効時は保存値を降格して読む」経路が撤去され、保存値がそのまま読まれることがテストで担保されている
- [ ] #5 .swiftlint.yml の custom rule feature_gate_direct_reference と対応する excluded 一覧が撤去され、swiftlint のベースライン差分がゼロである
- [ ] #6 FeatureGateTests / FeatureGateEnumerationTests が削除され、ゲート引数に依存していた既存テストが引数なしの呼び出しへ書き換わったうえで swift test が通る
- [ ] #7 .claude/CLAUDE.md の「フィーチャーゲート」節とコミット規約の (gate) スコープ規定が撤去されている
- [ ] #8 AppVersion.isPrerelease を残すか削るかの判断と理由が Implementation Notes に記録されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-03: 追加された TASK-263（フォルダー行の集約バッジ）/ TASK-264（変更ファイルのみ表示フィルター）も同じ FeatureGate 配下に入る。解除時は makeSidebarGitStatusLoader の guard に加えて TASK-264 のトグル UI 側のゲート分岐も撤去対象になる。

2026-08-06: ユーザー方針により、git 系機能が充実するまで着手しない。着手条件: ソース表示の git 差分（TASK-316〜322 の修正を含む）など同じ FeatureGate 配下の git 系機能が出揃い、サイドバー Git ステータスと合わせて stable 昇格をまとめて判断できる状態になったら再開する。

2026-08-10: 優先順位の整理で TASK-435(libgit2 移行)の後段へ置いた(ordinal 115000)。既存の着手条件「git 系機能が出揃ったら」に加えて、**バックエンドが libgit2 へ移る前に stable 昇格しない**という順序制約を足す。subprocess 版を stable に出してから差し替えると、同じ機能を 2 回リリース検証することになる。

2026-08-13: ユーザー方針の変更により本タスクの目的を差し替えた。「stable 昇格」ではなく「stable リリースを行わない前提で、ゲートの場合分けを維持するコストを削減する」ことが目的。これに伴い Description と Acceptance Criteria を全面的に書き換えた（旧 AC 2 件は「stable ビルドで常時表示される」という、もう検証しようのない条件だったため破棄）。

これにより、2026-08-06 の着手条件（git 系機能が出揃うまで着手しない）と 2026-08-10 の順序制約（libgit2 移行の前に stable 昇格しない）はいずれも失効した。後者の前提だった TASK-435 は 2026-08-10 に Done。

実施順序の決定: 本タスクを TASK-438 系・TASK-407 より先に行う。TASK-438.2「git が使えないとき差分表示モードを選択不可にする」は ModeSegments / MainMenuBuilder という本タスクの撤去対象と同じ箇所を触るため、先に 438 をやるとゲート可用性と git 可用性の二重判定を一度作って後で壊すことになる。ordinal を 100000（TASK-407 の 106000 より前）へ移した。
<!-- SECTION:NOTES:END -->
