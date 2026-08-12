---
id: TASK-408
title: ツリー表示の ← / h を階層移動ではなくツリー内の親行への選択移動にする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 06:09'
updated_date: '2026-08-10 08:11'
labels:
  - bug
dependencies: []
priority: medium
ordinal: 665000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーのキー操作が list（drillDown）と tree で非対称なため整理する。

## 現状（実測）

キー対応表は `SidebarKeyAction.action(key:modifiers:target:mode:)` (Viewer/SidebarKeyAction.swift:52) に一本化されており、表示モードは引数で渡る（モードごとの別ハンドラは無い）。

| キー | drillDown | tree |
|---|---|---|
| → / l / Return | フォルダ = 中へ入る（ルート変更） | 畳 = 展開 / 展開済 = 次の行へ |
| ← / h | 常に親へ（ルート変更） | 展開済フォルダ = 畳む / それ以外 = 親へ（ルート変更） |
| delete | 親へ（ルート変更） | 同左 |
| cmd+↑ | 親へ | 同左 |

## → の差は直さない（判断）

→ の意味がモードで違うことは他アプリの慣習どおりであり、変更しない。Finder 自身が、カラム表示（階層ごとに別ペイン）では → = 降りる、リスト表示（ツリーを平坦なリストとして見る）では → = 展開、と分かれている。befold の drillDown はカラム表示の 1 カラム版、tree はリスト表示に対応する。Xcode ナビゲータ / VS Code エクスプローラ / NERDTree もツリー側は例外なく → = 展開。ここを揃えると、かえってどちらかが慣習から外れる。

## 直すのは tree の ←（本題）

tree でファイルまたは畳んだフォルダを選択中に ← を押すと、ルートごと 1 階層上へ移動する（SidebarKeyAction.swift の tree 分岐、Viewer/FileListView+Keyboard.swift:112）。問題は 3 点。

1. 往復が非対称。→ で展開して子へ降りたのに、← は展開状態の中を戻らずツリーごと別の場所へ飛ぶ
2. tree の → は一度もルートを変えないのに、← だけがルートを変える
3. Finder / Xcode / VS Code / NERDTree はいずれも「← = 畳む、畳み済みか葉なら親フォルダの行へ選択を移す」の二段構えで、ルートは動かさない

## 整理の原則

- → / ← はモード内の移動にだけ使う（tree では展開・折りたたみと選択移動、drillDown では階層の出入り）
- ルートの変更は cmd+↑ と delete に集約する（両モードで同じ意味）

変更するのは tree の ← / h のみ。

| | 現状 | 変更後 |
|---|---|---|
| tree ← / h（展開済フォルダ） | 畳む | 畳む（変更なし） |
| tree ← / h（畳んだフォルダ・ファイル） | ルートを親へ | 親フォルダの行へ選択を移す |
| tree ← / h（最上位の行） | ルートを親へ | 何もしない（cmd+↑ / delete に委ねる） |
| drillDown ← / h | ルートを親へ | 変更なし |

## 同時に片付けるリファクタリング

- `.selectNext` が文脈で意味を変える。キー経由では「次の行へ」だが、ダブルクリック経由では「畳む」と解釈される (Viewer/FileListView.swift:301)。同じ値が 2 つの意味を持つのはバグ源なのでケースを分ける
- `enterSelected()` (Viewer/FileListView+Keyboard.swift:96) は private かつ参照ゼロの未使用コード。削除する

## 未確認

`.onKeyPress` が全キーを受けるため NSTableView 標準のタイプ先行入力が効かない可能性がある（未対応キーでは `.ignored` を返すので下位へ流れる想定）。実機で確認するまで断定しない。本タスクの対象外だが、確認して問題があれば別途起票する。

## 注意

tree 表示は `FeatureGate.isSidebarTreeEnabled` 配下のため、コミット件名に `(gate)` スコープを付ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tree で畳んだフォルダを選択中に ← / h を押すと、ルートは変わらず親フォルダの行へ選択が移る
- [x] #2 tree でファイルを選択中に ← / h を押すと、ルートは変わらず親フォルダの行へ選択が移る
- [x] #3 tree で展開済みフォルダを選択中の ← / h は従来どおり折りたたむ
- [x] #4 tree で最上位の行を選択中の ← / h は何もしない（ルートが変わらない）
- [x] #5 tree での cmd+↑ と delete は従来どおりルートを親へ移す
- [x] #6 drillDown のキー挙動は一切変わっていない
- [x] #7 上記すべてが SidebarKeyActionTests でモード別に検証されている
- [x] #8 キー経由の「次の行へ」とダブルクリック経由の「畳む」が別のケースに分離され、同じ値が文脈で意味を変えない
- [x] #9 未使用の `enterSelected()` が削除されている
- [x] #10 着手前に `/review-design` を 1 回実行し、結果を Implementation Plan に反映している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー（/review-design、実装前に 1 回実施）

裏付けの種類: 実測 = サブエージェントによるコード走査、コード参照 = file:line。

1. 判定の真実の源: 「親行」を **配列上の depth の連なり**で決める（現在行より前で depth がより小さい最初の行）。パス文字列の前置一致では決めない。visibleEntries は深さ優先で並び（SidebarRowBuilder.swift:85-92）、絞り込み中も SidebarTreeFilter.keepingAncestors が同じ「depth の連なり」で祖先を足し戻す（SidebarTreeFilter.swift:24-51）ため、既存の不変条件と同じ源を使うことになる。
2. 既存の不変条件との衝突: 「visibleEntries の添字 = NSTableView の行番号」（FileListModel.swift:262-267）に触らない。`..` 行は常に先頭・depth 0（SidebarNavigator+Expansion.swift:26-30）で、depth < 0 の行は存在しないため selectParent の行き先にはならない。depth 0 の行では .ignored（AC #4 を満たす）。
3. 消費経路の全列挙: SidebarKeyAction を消費するのは本番 2 箇所のみ（FileListView+Keyboard.swift:41-62 / FileListView.swift:299-315）。メニュー・ツールバーに「親へ」「展開/折りたたみ」相当は無い。ただし perform の switch は default を持つため、新ケース .selectParent を足してもコンパイラは漏れを教えない → **perform に明示的に case を書く**。
4. 新しい状態に対応する表示: 表示状態は増えない。選択が既存の可視行へ移るだけで、スクロール追従は selection の didSet が自動で行う（FileListModel.swift:98-103, 253-260）。専用の空表示・文言は不要。
5. ライフサイクル・順序: 非同期・キャッシュ・常駐化はいずれも増えない。該当しない。
6. 高頻度経路のコスト: 親行の後方走査はキー 1 打につき 1 回のみ（描画・監視コールバックからは呼ばない）。visibleEntries は計算プロパティなので **1 回だけ束縛して使い回す**（二重計算を避ける）。
7. 測るものと守るもの: ツリーの ← が「ルートを変えない」ことは、tree × 全ターゲット（nil 含む）で .navigateToParent を返さないことの網羅テストで測る。drillDown 側は既存テストで不変を測る。
8. 非同期の世代管理: 非同期取得は無い。該当しない。
9. 決めたことを守らせるもの: 上記 7 の網羅テストが「tree の ← はルートを変えない」を破ると落ちる形。また .selectNext の再解釈を撤去し、ダブルクリックが自前で .collapse を返す構造にすることで、同じ値が文脈で意味を変える形自体を無くす（AC #8）。

**レビューで方針を変えた点**
- 親行の探索を FileListView 側の private ヘルパーではなく `FileListModel.parentRow(of:)` に置く（行の並びの不変条件を持つ層に置き、ユニットテストから直接測れるようにする）。
- 既存テスト `SidebarKeyActionTests.doubleClickMatchesReturn` は「ダブルクリック == return」を固定している。本タスクは tree の展開済フォルダで意図的に分岐させるため、このテストをケース別の期待値へ書き換える（見落とすと失敗する）。
- tree で選択が無いときの ← は .selectParent（ハンドラ側で .ignored）に寄せ、tree からは .navigateToParent を一切返さない。

## 実装手順

1. SidebarKeyAction に `.selectParent`（ルートを変えずに親フォルダの行へ選択を移す）を追加する
2. backward(target:mode:): drillDown = .navigateToParent（変更なし）／tree = 展開済フォルダなら .collapse、それ以外（nil 含む）は .selectParent
3. doubleClickAction を forward の戻り値の再解釈ではなく自前判断にする（tree のフォルダ行のみ: 展開済 → .collapse / 畳 → .expand、他は forward と同じ）
4. FileListView.doubleTapGesture の `case .selectNext: onCollapseFolder` を `case .collapse:` に変える
5. FileListModel に `parentRow(of:)` を追加（visibleEntries を 1 回束縛し、現在行より前で depth がより小さい最後の行を返す。depth 0 なら nil）
6. FileListView+Keyboard の perform に `.selectParent` を明示的に足し、selectParentRow() を実装（親は必ずフォルダなので openIfFile は呼ばない。スクロールは selection の didSet 任せ）
7. 未使用の private enterSelected() を削除する
8. テスト: SidebarKeyActionTests（tree ← の 3 分岐 / tree ← が全ターゲットで .navigateToParent を返さない網羅 / drillDown 不変 / cmd+↑・delete 不変 / doubleClickMatchesReturn の書き換え）、FileListModel の parentRow テスト（depth 付き・絞り込み中・depth 0）、FileListViewTests で ← 経路が選択を親行へ移すこと
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装と検証（実測）

**変更点**
- `SidebarKeyAction` に `.selectParent` を追加。tree の ← / h は「展開済フォルダ → .collapse / それ以外（選択なしを含む） → .selectParent」になり、**tree からは .navigateToParent を一切返さない**（SidebarKeyAction.swift:100-118）。drillDown は `guard mode == .tree` の手前で従来どおり .navigateToParent。
- `doubleClickAction` を forward の戻り値の読み替えではなく自前判断へ変更（tree のフォルダ行のみ 展開済 → .collapse / 畳 → .expand）。消費側 FileListView.swift:311 の `case .selectNext:` を `case .collapse:` に変更し、`.selectNext` が文脈で意味を変える形を撤去。
- 親行の決定は新規 `FileListModel.parentRow(of:)`（FileListModel+TreeRows.swift）。visibleEntries の **depth の連なり**で決める（SidebarTreeFilter.keepingAncestors と同じ判定源）。depth 0（`..` を含む）は nil → .ignored。
- 未使用の private `enterSelected()` を削除。
- 選択移動後のスクロール追従は `FileListModel.selection` の didSet が既に行うため、selectParentRow では何も足していない（行き先は必ずフォルダなので openIfFile も呼ばない）。

**ファイル分割の理由**: parentRow を FileListModel.swift に直接置くと file_length（400 行）を 418 行で超えた（swiftlint 実測）。閾値を緩めず `FileListModel+TreeRows.swift` の extension へ分けた。新規ファイル 2 件のため `xcodegen generate` 実行済み。

**検証**
- `swift test --skip Integration --skip FileWatcherTests`: 1271 tests / 175 suites すべて成功。
- `xcodebuild build -scheme befold -destination 'platform=macOS'`: BUILD SUCCEEDED（新規ファイルの .xcodeproj 反映を確認）。
- swiftformat（--target befold befoldTests）: 0/195 files formatted（整形差分なし）。
- swiftlint: 変更前 79 件 → 変更後 77 件。増加分 2 件（file_length / identifier_name）は上記の分割と引数名 entryID で解消し、**変更したファイルの警告は 0 件**。

**既存テストの書き換え**: `doubleClickMatchesReturn` は「ダブルクリック == return」を固定していたが、tree の展開済フォルダで意図的に分岐させるため `doubleClickMatchesReturnExceptExpandedTreeFolder` + `doubleClickCollapsesExpandedTreeFolder` に分割した。

**担保（破れたら落ちるもの）**: `treeBackwardNeverChangesRoot` が tree × 全ターゲット（nil 含む）× ← / h で .navigateToParent / .navigateInto を返さないことを網羅する。個別ケースの列挙だけだと、あとから足したターゲットで穴が開く。

**未確認（本タスク対象外）**: Description の「`.onKeyPress` が NSTableView のタイプ先行入力を潰していないか」は実機確認していない。未対応キーで `.ignored` を返す形は変えていないため、本変更で状況は変わらない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ツリー表示の ← / h を階層移動から「ツリー内の親行への選択移動」に変更した。tree では ← が一切ルートを変えなくなり（ルート変更は cmd+↑ / delete に集約）、drillDown の挙動は不変。親行は visibleEntries の depth の連なりで決める FileListModel.parentRow(of:) が担い、最上位行では何も起きない。あわせて .selectNext をダブルクリックで「畳む」と読み替えていた形を撤去し、未使用の enterSelected() を削除した。検証: swift test 1271 件すべて成功、xcodebuild BUILD SUCCEEDED、swiftlint は変更ファイルで警告 0 件（全体 79→77）。
<!-- SECTION:FINAL_SUMMARY:END -->
