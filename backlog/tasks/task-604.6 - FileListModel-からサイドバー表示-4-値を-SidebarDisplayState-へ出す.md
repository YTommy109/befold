---
id: TASK-604.6
title: FileListModel からサイドバー表示 4 値を SidebarDisplayState へ出す
status: Done
assignee: []
created_date: '2026-09-09 00:02'
updated_date: '2026-09-09 01:12'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-604
priority: low
ordinal: 882000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/Viewer/FileListModel` グループは 393 行（本体 355 + `+Snapshot` 38）。TASK-585 で 418 → 393 へ返済済み（名前フィルターとスライドモードを `SidebarTransientState` へ、境界は「保存値の対を持つか」）。当時 7 値の移設案は 57 ファイル波及で見送られた。**その見送り分の一部がまだ返済余地として残っている。**

## 返済先（約 −20〜25 行、393 → 約 368〜373）

サイドバー表示 4 値のライブ値（`FileListModel.swift:174-192`）を `SidebarDisplayState`（`SidebarTransientState` と並ぶ兄弟型）へ。

決め手は実測: **4 値のうち 3 つ（`sortOrder` / `showHiddenFiles` / `layoutMode`）は `FileListModel` 内から一度も読まれていない**（宣言と init 代入のみ）。読み手は全部外側（`SidebarListingCoordinator` 10 参照 / `SidebarHeaderControlsModel` 7 / `ViewerDisplayOptionsApplier` 6 / `SidebarTreePresenter` 5）。モデルが「窓ごとの設定バッグ」として使われている状態で、規約の「複数の関心が 1 クラスに同居し始めたら凝集単位で分割する」に該当する。`showChangedFilesOnly` だけは内部でも使う（`:315,328`）。

`FileListModel` は `let display = SidebarDisplayState(settings:)` を 1 本持つ形（`transient` と同じ）。対応する値型 `SidebarDisplaySettings` は既存なので写像はそのまま使える。

## 返済対象にしないもの（根拠）

- **git 状態は ADR 0003 が固定**（`applyGitStatus` 1 関数への一本化）。ただし ADR の再検討トリップワイヤ #1 が「FileListModel に判定以外の責務が増え肥大化する」なので、この返済はそれに応える動き
- **`previewTarget`（`:116-125`）は ADR 0002 の単一導出点**。4 つの材料を同時に要るので出すと結合が増える
- `tableFocuser` は既に `SidebarTableFocuser` へ出済み

## 注意

- 波及は本番 15 ファイル / テスト 31 ファイル（上振れ見積り）。効果 20〜25 行に対して大きいので、閾値に押されるまで急がなくてよい
- `BefoldApp/befold/App/SidebarDisplaySettings.swift:122` に `extension FileListModel` があり、**ディレクトリが違うため 393 に合算されていない**。型の実サーフェスは 393 行より広い
- **この判断（何が切り出せて何が ADR 0002 / 0003 で固定されているか）を `FileListModel` の型 doc へ残すこと。** 残さないと次に閾値へ近づいたときに 3 度目の同じ調査が走る（TASK-585 → TASK-604 で既に 2 回）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバー表示 4 値が SidebarDisplayState へ出ている（または見送る判断と理由が記録されている）
- [x] #2 FileListModel の型 doc に、何が切り出せて何が ADR 0002 / 0003 で固定されているかが書いてある
- [x] #3 swift test が通り、サイドバーの表示切り替えが実機で動く
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー（/review-design、2026-09-09）を反映した方針

### 目的の置き直し

行数削減（-23 行）は副次。**主目的は「4 値を変える入口」を構造で固定すること。**
現状「`applyDisplayChange` の 1 本だけ」は doc コメントにしかなく、既に破れている
（`ViewerDisplayOptionsApplier.swift:33,41` が `fileListModel.sortOrder` /
`.showHiddenFiles` へ直接代入。doc は「CLI 上書きは例外」と書くが区別が構造に無い）。

### SidebarDisplayState（新規・`befold/Viewer/`、`SidebarTransientState` の兄弟）

- `private(set) var settings: SidebarDisplaySettings` を **1 本**持つ。
  4 つの stored var を並べ直さない——@Observable の粒度は論点にならない
  （4 値が変わるのは操作の瞬間だけで、うち 3 つは直後に `refreshFileList` →
  `entries` 代入でサイドバー全体が再評価される: `SidebarListingCoordinator.swift:86-105`）
- 読み側は転送 computed 4 本（`sortOrder` / `showHiddenFiles` /
  `showChangedFilesOnly` / `layoutMode`）で `model.display.sortOrder` の 2 ホップに保つ
- 書き込みは 2 メソッドだけ。`apply(_ change: SidebarDisplayChange)` と、
  CLI 上書き用の `applyCLIOverride(...)`。例外の 2 本目も型が名前で区別する形になる

### SidebarDisplaySettings に `applying(_ change:)` を足す

純粋関数・`default` を置かない。既存の `isOn(_:)`（読み・`default` なし・TASK-592）と
読み書きが対になり、切り替えを足したときの網羅をコンパイラが見張る。
`SidebarListingCoordinator` は「ライブ値更新 → 既定値の書き戻し → 値ごとの後処理」の
**順序制御だけ**を持ち続ける（後処理は移さない）。

### 採らない案

`FileListModel` が `var displaySettings: SidebarDisplaySettings` を 1 本持つ形。
行数削減も波及もほぼ同じだが、値が `FileListModel` に残るため起票理由
（ADR 0003 の再検討トリップワイヤ #1「判定以外の責務が増え肥大化する」）に応えない。
20 個以上のプロパティを持つ型の上で `private(set)` にしても境界として弱い。

### ついでに確認する（別件・小）

`FileListModel.init` の `display: SidebarDisplaySettings = .initial`。
`SidebarDisplaySettings.initial` の doc は「本番のウィンドウ生成経路では使わない」と
書いているが、既定引数なので渡し忘れがコンパイルエラーにならない（TASK-319 と同型）。
外せるか確認し、テストの都合で残すなら理由を doc に書く。

### AC #2（型 doc）に書くこと

`FileListModel` の型 doc へ「何が出せて何が固定か」を残す。
- 出した: サイドバー表示 4 値 → `SidebarDisplayState`（本タスク）、
  名前フィルター・スライドモード → `SidebarTransientState`（TASK-585）、
  フォーカス → `SidebarTableFocuser`
- 固定: git 状態の反映ガードは ADR 0003 が `applyGitStatus` 一本化を決めている。
  `previewTarget` は ADR 0002 の単一導出点で、4 つの材料を同時に要るため出すと結合が増える

### 実測（着手前）

- `FileListModel` グループ 393 行（`check-type-group-size.sh`）。見積り 393 → 約 370
- 波及 29 ファイル / 93 参照（`rg` 実測。本番 21 ファイル）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- `befold/Viewer/SidebarDisplayState.swift`（新規 67 行）: `private(set) var settings:
  SidebarDisplaySettings` を 1 本持ち、読みは転送 computed 4 本（`model.display.sortOrder`）。
  書き込み口は `apply(_ change:)`（利用者の操作、既定値の書き戻しと対）と
  `applyCLIOverride(sortOrder:showHiddenFiles:)`（この起動限りの上書き、既定値を書かない）の 2 つだけ。
- `SidebarDisplaySettings.applying(_ change:)` を追加（純粋・`default` なし）。既存の
  `isOn(_:)` と読み書きが対になり、切り替えを足したときの網羅をコンパイラが見張る。
- `SidebarListingCoordinator.applyDisplayChange` は値ごとの switch を捨て、
  「ライブ値更新 → 書き戻し → 値ごとの**後処理**」だけを持つ形に畳んだ（208 → 202 行）。
- `FileListModel.displaySettings` extension（`SidebarDisplaySettings.swift` にあった）は撤去。

## 設計レビューで方針が変わった点

- **主目的を行数削減から「入口の固定」へ置き直した。** 「変更の入口は
  `applyDisplayChange` の 1 本」は doc コメントにしかなく、**既に破れていた**
  （`ViewerDisplayOptionsApplier.swift` が `fileListModel.sortOrder` /
  `.showHiddenFiles` へ直接代入。doc は「CLI 上書きは例外」と書くが区別が構造に無い）。
- **4 つの stored var を並べ直さず `settings` 1 本にした。** @Observable の粒度は
  論点にならない——4 値が変わるのは操作の瞬間だけで、うち 3 つは直後に
  `refreshFileList` → `entries` 代入でサイドバー全体が再評価される。
- 代替案（`FileListModel` が `var displaySettings` を 1 本持つ）は不採用。値が
  `FileListModel` に残り、起票理由（ADR 0003 のトリップワイヤ #1）に応えないため。

## 実測

- 行数: `FileListModel` グループ 393 → **388**（見積り 368〜373 に届かない）。差は AC #2 の
  型 doc 9 行と `display` プロパティ / init の doc。純粋な移設ぶんは -20 行で見積りどおり。
  新設 `SidebarDisplayState` 67 行、`SidebarDisplaySettings` 189 → 192、
  `SidebarListingCoordinator` 208 → 202。
- 波及: 実際に触ったのは 46 ファイル（本番 21 / テスト 25）。読みは機械置換、
  書きは 26 箇所（本番 6・テスト 20）を `apply` / `applyCLIOverride` へ。
- `swift test`: 1945 tests / 320 suites すべて成功（`applying` の新規テスト 3 本を含む）。
- swiftlint: main とのベースライン差分ゼロ。swiftformat: 変更なし。

## 実機確認（AC #3）

Debug ビルドを起動し、System Events で「表示」メニューを操作して確認した。
- 「不可視ファイルを表示」→ クリック後にタイトルが「不可視ファイルを隠す」へ反転
- 「サイドバーをツリー表示」→ クリック後にチェックマーク ✓ が付く
- **その状態で別ファイルを新しい窓で開くと、両方が引き継がれていた**
  （`recordSettings` の既定値書き戻しが効いている）
- 両方を戻すと元のタイトル / チェック無しへ復帰

## テストの書き換えについて

`private(set)` にしたため、テストの初期状態づくり 20 箇所が
`model.display.showChangedFilesOnly = true` から `model.display.apply(.toggleChangedFilesOnly)`
へ変わった。既定値からの 1 回のトグルなので意味は同じで、かつ実際の変更経路を通る。
`layoutMode = .drillDown`（既定と同値の代入）だった 1 箇所は `#expect` に置き換えた。
<!-- SECTION:NOTES:END -->
