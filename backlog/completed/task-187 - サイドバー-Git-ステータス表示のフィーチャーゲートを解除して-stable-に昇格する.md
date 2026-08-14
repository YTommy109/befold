---
id: TASK-187
title: FeatureGate 機構を撤去し、ゲート配下の 3 機能を常時有効化する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-28 14:23'
updated_date: '2026-08-13 15:02'
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
- [x] #1 FeatureGate.swift が削除され、リポジトリ内のプロダクトコードに FeatureGate への参照が 0 件である（rg 'FeatureGate' で BefoldApp 配下のヒットが 0）
- [x] #2 3 機能（サイドバー git ステータス / ソース表示の git 差分 / サイドバーのツリー展開）が、ビルド構成やバージョン文字列によらず常時有効である
- [x] #3 ゲート値を下位へ渡していた引数（isSourceDiffEnabled / isChangedFilesOnlyAvailable / isTreeLayoutAvailable / isGitStatusAvailable）が宣言ごと撤去され、デフォルト引数による復活余地も残っていない
- [x] #4 SidebarDisplayPreference と PerFileStateStore の「無効時は保存値を降格して読む」経路が撤去され、保存値がそのまま読まれることがテストで担保されている
- [x] #5 .swiftlint.yml の custom rule feature_gate_direct_reference と対応する excluded 一覧が撤去され、swiftlint のベースライン差分がゼロである
- [x] #6 FeatureGateTests / FeatureGateEnumerationTests が削除され、ゲート引数に依存していた既存テストが引数なしの呼び出しへ書き換わったうえで swift test が通る
- [x] #7 .claude/CLAUDE.md の「フィーチャーゲート」節とコミット規約の (gate) スコープ規定が撤去されている
- [x] #8 AppVersion.isPrerelease を残すか削るかの判断と理由が Implementation Notes に記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FeatureGate 型ごと削除（D-1(a)）。FeatureGate.swift / FeatureGateTests.swift / FeatureGateEnumerationTests.swift / .swiftlint.yml の custom rule feature_gate_direct_reference を**同一コミット**で削除する（割れると列挙テストが必ず落ちる）。
2. ゲート引数 4 種を宣言ごと撤去（デフォルト引数による復活余地を残さない）。
   - ViewerWindowAssembler: makeSidebarGitReader は関数ごと削除して呼び出し元でインライン生成（D-3(a)）。makeChangedFilesOnlyToggle / makeSidebarTreeLayoutToggle は戻り値を非 Optional の () -> Void にする。
   - SidebarDisplayPreference.init: 引数 2 本を削除し、保存値をそのまま読む（降格撤去）。
   - PerFileStateStore → DisplayModeStore: isSourceDiffEnabled プロパティ・init 引数・降格 guard を撤去。supportsDiffDisplay の種別ゲートは残す。
   - ModeSegments: modes(isSourceDiffEnabled:) を削除し all を配列リテラルへ（D-5(a)）。
   - MainMenuBuilder / +ViewMenu: addDisplayModeItems / makeViewMenuItem / addSidebarItems / addSidebarTreeLayoutItem / addChangedFilesOnlyItem からゲート引数と guard を撤去。
   - SidebarHeaderControlsModel: init の 2 引数と guard/if を撤去。
   - SidebarGitReading: statusStore を非 Optional 化し guard を撤去。
3. SidebarHeaderView / FileListView の onToggleChangedFilesOnly / onToggleSidebarTreeLayout を非 Optional 化（D-4(a)）。本番で nil が渡る経路はゲート guard だけであることを確認済み。onToggleHiddenFiles は対象外（別件）。
4. GitDiffLoader? の 3 階層 Optional は本タスクでは非 Optional 化しない（D-2(b)）。makeDiffLoader() を削除し ViewerWindowManager.init のデフォルト引数を GitDiffLoader() にする。Optional はテスト注入のためだけに残す旨を doc に明記し、残りは別タスクへ。
5. テスト: false を渡す OFF 側検証ケースを削除、true を渡す呼び出しは引数を落とす。FeatureGate 直読み（try #require / 三項）は常時有効の形へ書き換え。MainMenuBuilderTests.viewMenuShortcutsAreUnique はパラメタライズを外して残す（ゲート検証ではなくキー等価の重複検査が主眼）。ViewerWindowAssemblerGateTests はファイルごと削除。
6. AC#4 の担保: SidebarDisplayPreference / DisplayModeStore が保存値をそのまま読むことを、保存値 ON/tree/.diff → そのまま読まれる、のテストで固定する。
7. 設定・スクリプト: scripts/check-gate-commit-scope.sh 削除、setup-git-hooks.sh から commit-msg 行を削除、.claude/commands/release-notes.md と release.md の (gate) 除外規則を削除。
8. ドキュメント: .claude/CLAUDE.md の「フィーチャーゲート」節・(gate) スコープ規定・ファイル分割手順の 2 行、docs/dev/development.md のフック表 1 行と「(gate) スコープの強制」節、docs/dev/native-app-design.md の 3 箇所、ルート CLAUDE.md の分類基準 1 項目。docs/superpowers/ 配下は履歴文書なので変更しない。
9. xcodegen generate → swift build → swift test → swiftlint を main ベースライン（54 件）と比較してゼロ差分を確認 → markdownlint-cli2 → check-doc-symbols.sh。
10. AC#8: AppVersion.isPrerelease の存廃判断を Implementation Notes に記録する。

11. /review-design の結果を反映（2026-08-13）:
- F1: ModeSegments.modes(isSourceDiffEnabled:) を doc で名指ししている 6 箇所（SidebarRowIndent:8 / FileListView:86 / SidebarKeyAction:8 / SidebarDisclosureState:34 / ViewerToolbarController:102 / ModeSegments:26,45）を同一コミットで書き換える。check-doc-symbols.sh は Swift コメントを検査しないため自動検知されない。
- F2: ViewerWindowAssemblerGateTests を全削除せず、ON 側 1 ケース（statusStore の配線）を残す。rg 実測で makeSidebarGitReader / SidebarGitReader( を触るテストは同ファイルのみ。
- F3: GitDiffLoader? は ViewerWindowManager 階層を非 Optional 化し、Optional を ViewerWindowController / ViewerDiffPresenter の 2 階層（テスト注入）に限定する。doc に「本番の可否判定は canSelectDiffMode が唯一の源」と明記。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-03: 追加された TASK-263（フォルダー行の集約バッジ）/ TASK-264（変更ファイルのみ表示フィルター）も同じ FeatureGate 配下に入る。解除時は makeSidebarGitStatusLoader の guard に加えて TASK-264 のトグル UI 側のゲート分岐も撤去対象になる。

2026-08-06: ユーザー方針により、git 系機能が充実するまで着手しない。着手条件: ソース表示の git 差分（TASK-316〜322 の修正を含む）など同じ FeatureGate 配下の git 系機能が出揃い、サイドバー Git ステータスと合わせて stable 昇格をまとめて判断できる状態になったら再開する。

2026-08-10: 優先順位の整理で TASK-435(libgit2 移行)の後段へ置いた(ordinal 115000)。既存の着手条件「git 系機能が出揃ったら」に加えて、**バックエンドが libgit2 へ移る前に stable 昇格しない**という順序制約を足す。subprocess 版を stable に出してから差し替えると、同じ機能を 2 回リリース検証することになる。

2026-08-13: ユーザー方針の変更により本タスクの目的を差し替えた。「stable 昇格」ではなく「stable リリースを行わない前提で、ゲートの場合分けを維持するコストを削減する」ことが目的。これに伴い Description と Acceptance Criteria を全面的に書き換えた（旧 AC 2 件は「stable ビルドで常時表示される」という、もう検証しようのない条件だったため破棄）。

これにより、2026-08-06 の着手条件（git 系機能が出揃うまで着手しない）と 2026-08-10 の順序制約（libgit2 移行の前に stable 昇格しない）はいずれも失効した。後者の前提だった TASK-435 は 2026-08-10 に Done。

実施順序の決定: 本タスクを TASK-438 系・TASK-407 より先に行う。TASK-438.2「git が使えないとき差分表示モードを選択不可にする」は ModeSegments / MainMenuBuilder という本タスクの撤去対象と同じ箇所を触るため、先に 438 をやるとゲート可用性と git 可用性の二重判定を一度作って後で壊すことになる。ordinal を 100000（TASK-407 の 106000 より前）へ移した。

2026-08-14 実装完了。

## AC#8 の判断: AppVersion.isPrerelease は残す

FeatureGate.swift:83 が唯一の本番利用者だったため撤去後は本番未使用になるが、削除しない。理由:
- AppVersion は BefoldCLI の public API（AppVersion.swift:14 が public static func）であり、本アプリ以外からの利用可能性を閉じる判断を本タスクで下す理由がない
- dev リリースのバージョン文字列（v1.12.4-dev.5 形式）は release.yml がタグから注入し続けるため、プレリリース判定そのものは意味を失っていない
- AppVersionTests が挙動を固定しており、維持コストはゼロに近い
（.claude/CLAUDE.md「デッドコード削除前にテストが失う網羅を確認する」の型に沿う判断）

## 設計判断（/review-design の結果を反映）

- F1: ModeSegments.modes(isSourceDiffEnabled:) を doc で名指ししていた 6 箇所を同一コミットで書き換えた。check-doc-symbols.sh の既定検査対象は CLAUDE.md 2 ファイルのみ（scripts/check-doc-symbols.sh:24-25）で Swift コメントは検査しないため、自動検知されない型だった。
- F2: ViewerWindowAssemblerGateTests を全削除せず、ON 側 1 ケースを ViewerWindowAssemblerGitReaderTests へ縮小して残した。rg -l 実測で makeSidebarGitReader / SidebarGitReader( を触るテストは同ファイルのみであり、全削除すると statusStore の配線を測るテストがゼロになるため。型名は swiftlint の type_name（40 文字上限）に合わせて短縮した。
- F3: GitDiffLoader の Optional は ViewerWindowManager 階層で解消（非 Optional 化 + makeDiffLoader() 撤去）し、ViewerWindowController / ViewerDiffPresenter の 2 階層はテスト注入のため Optional のまま残した。本番の差分可否判定は ViewerCapabilities.canSelectDiffMode が唯一の源。この 2 階層の非 Optional 化は別タスク候補（テスト 5 ファイルの書き換えを伴う）。
- onToggleHiddenFiles はゲート対象外のため Optional のまま。SidebarHeaderView / FileListView の 3 クロージャの Optional 性を揃えるのは本タスクのスコープ外。

## UserDefaults の扱い

保存キー（ShowChangedFilesOnly / SidebarLayoutMode / ViewerDisplayModes）の意味・型・粒度は変えず、読み出し時の降格だけを外した。旧キーの読み手は 0 にならないため、.claude/CLAUDE.md「UserDefaults キーの廃止・改名」節の移行手順は適用外。stable v1.12.3 のユーザーはゲート OFF で切替手段が露出しなかったため、これらのキーに ON が保存されている状態は作れず、移行も不要。

## 検証

- swift test: 1504 tests / 238 suites すべて通過（2 回実行）
- 新規 3 テスト（保存値がそのまま読まれる）は、降格を戻すと 4 件の Expectation failed で落ちることを実測済み（空振りしていない）
- swiftlint: origin/main を git archive で別ディレクトリへ展開して測ったベースライン 54 件と完全一致（差分ゼロ）
- swiftformat: 0/16 files formatted（整形差分なし）
- scripts/check-doc-symbols.sh: OK / --self-test も OK
- markdownlint-cli2: 70 files, 0 issues
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FeatureGate 機構を型ごと撤去し、サイドバー git ステータス / ソース表示の git 差分 / サイドバーのツリー展開の 3 機能を常時有効化した。ゲート値を下位へ渡していた 4 引数（isSourceDiffEnabled / isChangedFilesOnlyAvailable / isTreeLayoutAvailable / isGitStatusAvailable）を宣言ごと撤去し、SidebarDisplayPreference・DisplayModeStore の「無効時は保存値を降格して読む」経路と、SidebarGitReader.statusStore・サイドバーヘッダーの 2 クロージャの Optional 性（＝ゲート表現）も併せて解消した。swiftlint custom rule feature_gate_direct_reference、commit-msg フック check-gate-commit-scope.sh、/release-notes と /release の (gate) 除外規則、.claude/CLAUDE.md のフィーチャーゲート節とコミット規約、docs/dev の 2 文書も撤去した。撤去後に「ゲート引数がデフォルト引数で復活する」余地が無いことは、FeatureGate 型そのものが存在しない（参照すればコンパイルエラー）という構造で担保される。検証: swift test 1504 tests / 238 suites 通過、新規 3 テストは降格を戻すと落ちることを実測、swiftlint は origin/main ベースライン 54 件と差分ゼロ、swiftformat 整形差分なし、check-doc-symbols.sh と markdownlint-cli2 も通過。
<!-- SECTION:FINAL_SUMMARY:END -->
