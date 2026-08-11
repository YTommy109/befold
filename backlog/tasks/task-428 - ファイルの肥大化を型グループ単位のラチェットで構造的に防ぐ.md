---
id: TASK-428
title: ファイルの肥大化を型グループ単位のラチェットで構造的に防ぐ
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-10 12:32'
updated_date: '2026-08-11 13:51'
labels: []
dependencies: []
documentation:
  - docs/dev/rules/product-code.md
priority: high
type: chore
ordinal: 104000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ファイルが責務を抱えたまま肥大化し、限界に達してから後追いで分割タスクを起票する、というサイクルが繰り返されている。実績: TASK-411（ViewerWindowController 978 行, Done）/ TASK-426（ViewerWindowManager 536 行, To Do）/ TASK-420（viewer-main.js 1,888 行, To Do）/ コミット e94161d（レビュー対応で肥大化した SidebarNavigator 系を分割）。

## 現状の穴（実測）

規約は既に存在する。`docs/dev/rules/product-code.md:123-137` の「責務分離」節に「**SwiftLint の行数閾値は上限であって目標ではない**」があり、`.claude/skills/review-architecture.md` にも「ファイル行数が過度に大きくないか(目安: 200行超で要確認)」がある。それでも 978 行まで育った。欠けているのは規約ではなく強制機構であり、穴は 2 つ。

1. **ラチェットが無い**: `BefoldApp/.swiftlint.yml:13-15` の `file_length` は warning 400 / error 1000。400 超は warning なのでビルドも CI も落ちない（`.github/workflows/ci.yml` に SwiftLint を strict で回すステップは無く、SwiftLint はビルドツールプラグインとして走るだけ）。さらに、一度 400 を超えたファイルは main 側にも同じ警告が立つため、401 行から 978 行への成長が `/swiftlint-baseline` の「新規警告」として検出されない。唯一の検知経路がこのベースライン比較だけなので、超過後の成長は完全に無防備。
2. **extension 逃げが数値上は有効**: TASK-411 の Description の原文 —「すでに +Capabilities / +Diff / +WindowHelpers の 3 拡張が存在するが、これは同じ行数上限を回避するために切られたものであり責務の分離にはなっていない」。`file_length` はファイル単位の判定なので、責務を分けずにファイルだけ割れば必ず通る。

`.claude/CLAUDE.md` は「同型のバグが 2 回目に出たら、個別修正をやめて構造で塞ぐ」「ルールへの明文化は 2 回目の対処として数えない」と定めている。本件は 4 回目であり、規約追加だけの対処はこの規定に反する。

## 採る方針

数値の強制と責務の判断を別レイヤーに分ける。

- **機械レイヤー**: 判定単位を「ファイル」ではなく「型グループ」（`Foo.swift` + 同ディレクトリの `Foo+*.swift` の合計行数）にして extension 逃げを封じる。現状値をベースラインへ凍結し、増加のみを禁止するラチェットとして運用する。強制は段階的に効かせる（pre-commit は警告、CI はブロック）。
- **意味レイヤー**: 責務の混在は数値では捕まらないため、レビューフェーズを設計時・PR 時・タスク完了時の 3 点に置く。

ベースラインは恒久的な仕組みではなく、負債返済期間中の足場。全件が閾値以下になった時点で撤去し、単純な閾値強制へ畳む（サブタスクの最終段）。

## 負債の実測（起票時点）

`find BefoldApp -name "*.swift" -not -path "*/.build/*" | xargs wc -l` による。Swift ファイル 401 件・総計 48,153 行のうち 400 行超は 7 件。

- プロダクト 3 件: `BefoldApp/befold/App/ViewerWindowManager.swift`(536, TASK-426 で起票済み) / `BefoldApp/befold/App/AppDelegate.swift`(495) / `BefoldApp/befold/Viewer/ViewerStore.swift`(492)
- テスト 4 件: `ViewerWindowControllerTests.swift`(585) / `ViewerStoreTests.swift`(540) / `GitCommandRunnerTests.swift`(507) / `QuickOpenModelTests.swift`(452)

なお上記はファイル単位の数値であり、型グループ単位で集計すると `ViewerWindowController` 系（本体 + `+Assembly` + `+DiffPresentation` ほか）のように合算で閾値を超えるグループが新たに現れる見込み。初期ベースラインの実測はサブタスク 1 で行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 型グループ単位（Foo.swift + Foo+*.swift の合算）の行数が、ベースラインを超えて増加したときに CI が落ちる
- [x] #2 新規に追加された型グループが閾値を超えたときに CI が落ちる
- [x] #3 責務の混在を見るレビューが、設計時・PR 時・タスク完了時の 3 点から回るよう配線されている
- [ ] #4 全サブタスク完了後、ベースライン方式が撤去され単純な閾値強制に畳まれている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## スコープの確認事項（起票時、未決）

型グループ単位のラチェットは Swift の `Type+Feature.swift` 命名規約に依存するため、**JavaScript は対象外**として設計している。しかし肥大化の実害は JS 側にもあり、`BefoldApp/BefoldKit/Resources/viewer-main.js` は 1,888 行で TASK-420 が起票済み（Swift の最大値 585 行より大きい）。

現時点の扱い: JS の現存負債は TASK-420 で個別に返済する。JS にも同種の再発防止機構を入れるかどうかは、Swift 側の仕組みが動き出してから（TASK-428.3 完了後に）判断する。JS はファイル単位の素朴な行数閾値でも extension 逃げが存在しないため、Swift ほど凝った仕組みは要らない可能性が高い。

## JS の扱いを確定した（2026-08-10）

起票時に「JS へ再発防止機構を入れるかは TASK-428.3 完了後に判断する」と保留していた件は、ADR 0005（docs/adr/0005-bundle-viewer-js-with-esbuild.md, decision-5）で方針が決まった。JS はバンドル方式へ移行し、モジュール境界を持たせる（TASK-432）。

これにより、JS 側で本タスクの型グループ相当の仕組みを別途作る必要は無くなる見込み。モジュール境界があれば分割が自然な操作になり、行数の閾値はファイル単位の素朴な判定で足りる（extension 逃げに相当する回避手段が JS には無い）。TASK-432.2 の完了後に、JS へ単純なファイル単位の行数閾値を足すかどうかを判断する。

## 進捗（2026-08-11）

428.1 / 428.2 / 428.3 / 428.4 を完了。機械レイヤー（型グループ単位のラチェット: 集計 → pre-commit 警告 → CI ブロック）と意味レイヤー（responsibility-reviewer を 3 点へ配線）の両方が動いている。AC #1〜#3 を確認済み。

**AC #4（ベースライン方式の撤去）は着手不可**。TASK-428.5 の依存 4 件（TASK-426 / 429 / 430 / 431）がいずれも To Do で、ベースラインには 12 グループが残っている。これらが完了してベースラインが空になれば着手できる。

## 起票時の見積もりとのズレ（返済タスクの不足）

型グループ単位の初期ベースライン（12 件）に対し、返済タスクが起票されているのは 4 件分だけで、次の 5 グループには返済タスクが無い。うち上位 2 件は起票時のファイル単位の実測（7 件）では見えていなかったもので、ファイル単位の最大値 585 行を大きく上回る。

| グループ | 行数 | 返済タスク |
|---|---|---|
| BefoldRenderKit/ViewerRenderer | 1300 | 無し |
| befold/App/ViewerWindowController | 1255 | 無し（TASK-411 で分割済みだが合算では増加） |
| befold/App/SidebarNavigator | 611 | 無し |
| befold/Viewer/FileListModel | 459 | 無し |
| befold/Viewer/FileListView | 437 | 無し |

TASK-428.4 の実地確認で responsibility-reviewer を e94161d へ回した結果も、SidebarNavigator について High 1 件（分割が責務分離になっていない）を含む 3 件を指摘しており、返済対象であることを裏付けている。

TASK-428.5 を着手可能にするには、この 5 件の返済タスク起票と依存追加が必要（ユーザー判断待ち）。

## 返済タスクを起票した（2026-08-11）

ベースラインの 12 グループすべてに返済タスクが対応するようにし、TASK-428.5 の依存へ全件を追加した（依存 10 件）。これで「ベースラインが空になったら 428.5 が着手可能」という関係が backlog 上で閉じる。

| グループ | 行数 | タスク |
|---|---|---|
| ViewerRenderer | 1300 | TASK-440（新規） |
| ViewerWindowController | 1255 | TASK-441（新規） |
| SidebarNavigator | 611 | TASK-442（新規） |
| AppDelegate | 562 | TASK-429（既存） |
| ViewerWindowManager | 543 | TASK-426（既存） |
| ViewerStore | 492 | TASK-430（既存） |
| ViewerBridge | 470 | TASK-444（新規） |
| FileListModel / FileListView | 459 / 437 | TASK-443（新規、2 グループを 1 タスク） |
| ViewerWindowControllerTests / ViewerStoreTests / QuickOpenModelTests | 585 / 540 / 452 | TASK-431（既存） |

未対応グループ数はゼロ。なお TASK-431 が起票時に対象としていた GitCommandRunnerTests.swift（507 行）は現在リポジトリに存在せず、テストの対象は 4 件ではなく 3 件（TASK-431 の Notes へ記録済み）。

## AC #4 の到達条件を見直した（2026-08-11、優先順位評価）

「依存 10 件が全て完了すればベースラインが空になる」という前提が崩れていることを実測で確認した。ベースラインに残る `852  BefoldApp/befold/App/ViewerWindowController` の返済タスク TASK-441 は Done であり、その AC は 400 行到達不能の実測（init の Parameter doc 約 120 行 + 移動不能な @objc アクション 13 個）を根拠に 900 行へ書き換えられている。852 → 400 を目指す To Do タスクは存在しない。

**決定（ユーザー判断）**: 追加の返済タスクは起票せず、TASK-428.5 の設計を「ベースライン撤去 → 単純な閾値強制」から「ベースライン撤去 → 閾値 + 理由付きの恒久例外リスト」へ変更した。TASK-428.5 の AC を 4 件から 6 件へ書き換え済み。AC #4（ベースライン方式の撤去）はこの新しい形で満たす。
<!-- SECTION:NOTES:END -->
