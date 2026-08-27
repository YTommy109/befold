---
id: TASK-558
title: 共有 Preference の init 引数からデフォルト値を外す
status: Done
assignee: []
created_date: '2026-08-27 05:28'
updated_date: '2026-08-27 05:42'
labels: []
dependencies: []
ordinal: 808000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ViewerWindowManager.init` と `ViewerWindowController.init` の `codeFontPreference` には `= CodeFontPreference()` のデフォルト値が付いている。これは TASK-319（`DiffDisplayPreference` が窓ごとに生成され 2 窓でトグルが同期しなかった）と同型の穴で、**渡し忘れがコンパイルエラーにならず静かに別インスタンスになる**。

`AppStores` の doc コメント自体が「個別に引数で配ると渡し忘れがコンパイルエラーにならないため、束ねた 1 個を配る」と書いており、デフォルト値付きの引数はその方針と食い違っている。

TASK-557.2 で足した `csvNumberFormatPreference` は既にデフォルト値を付けていない（実装前の /review-design で指摘した）。既存分を揃える。

## 対象

`rg 'Preference = \w+Preference\(\)'` で洗う。少なくとも `codeFontPreference` の 2 箇所（ViewerWindowManager / ViewerWindowController）。`findOptionsPreference` にも同じ形がある（`= FindOptionsPreference()`）ので、共有前提かどうかを 1 件ずつ確かめる。

## 注意

デフォルト値を外すと実構築サイト（本番 1 + テスト 4〜5）へ引数追加が要る。TASK-557.2 の実測では `ViewerWindowManager` の実構築は 5 箇所だけで、`grep -c 'ViewerWindowManager('` の 73 件は大半が `MockedViewerWindowManager(` の部分一致だった。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 共有前提の Preference / Store を受け取る init 引数にデフォルト値が残っていない
- [x] #2 デフォルト値を外した引数について、実構築サイトがすべて AppStores の同じインスタンスを渡している
- [x] #3 対象を洗った結果（外した引数と、共有前提でないため残した引数）が Implementation Notes に列挙されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 対象を洗う: ViewerWindowManager.init / ViewerWindowController.init の「型名と同じ型の新しいインスタンスを既定値にしている」引数を列挙する。
2. AppStores が 1 個持つもの（共有前提）の既定値を外す。
3. 共有インスタンスの受け渡しではなく「実装の選択」である引数は残し、理由を doc コメントに書く。
4. doc コメントだけでは今回と同じ形で破れるので、init の宣言をソースから読んで検査するテストを足す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 洗った結果

`ViewerWindowManager.init` / `ViewerWindowController.init` の既定値付き引数 14 件を 1 件ずつ判定した。

### 既定値を外したもの（6 引数・両ファイル合わせて 9 箇所）

いずれも `AppStores` が唯一のインスタンスを持つ共有物で、渡し忘れが静かに別インスタンスになる形だった。

| 引数 | 置き場 |
| --- | --- |
| `displayDefaults` (SidebarDisplayDefaults) | manager / controller |
| `findOptionsPreference` | manager / controller |
| `codeFontPreference` | manager / controller |
| `perFileState` (PerFileStateStore) | manager / controller |
| `recentRepositoriesStore` | manager |

### 残したもの（共有前提でない、または共有の担保が別にある）

| 引数 | 残した理由 |
| --- | --- |
| `fileReader: any FileReading = DefaultFileReader()` | 共有インスタンスの受け渡しではなく**実装の選択**（本番実装 ⇄ テストの InMemoryFileReader）。型が違うので「同じ型を作り直す」形にならない |
| `gitFileIndex: any GitFileIndexing` | 同上。manager は `GitCommandFileIndex()`、controller は `DisabledGitFileIndex()` と**別実装**が既定で、意図的な縮退 |
| `gitStatusStore: GitStatusStore = GitStatusStore()` (controller) | 既定は「git 状態を持たない縮退状態」。manager 側の doc コメントが「既定は無効化状態(常に空)で、本番のルート解決付きインスタンスは AppDelegate が差し込む」と明記している。gitFileIndex の `DisabledGitFileIndex` と同じ位置づけ |
| `diffLoader: GitDiffLoader = GitDiffLoader()` (manager) | **manager が唯一の持ち主**で AppStores には無い。既定値は「共有インスタンスを渡し忘れた」ではなく「その 1 つを作る」意味。外すと AppDelegate が直に生成することになり、所在がかえって散る（AppStores へ移すかは別の判断で、本タスクでは触らない） |

### 実構築サイト（実測）

manager 5 箇所（本番 1・テスト 4）、controller 3 箇所（本番 1・テスト 2）。`grep -c 'ViewerWindowManager('` の 73 件は大半が `MockedViewerWindowManager(` の部分一致で、実際の構築ではなかった（起票時の想定どおり）。

## doc コメントでは守られないので検査を付けた

この規則はもともと `AppStores` と `DiffDisplayPreference` の doc コメントに書かれていた。**それでも破れていた**のが本タスクの起点なので、同じ手当て（コメントを足す）で終わらせず、`SharedDependencyDefaultsTests` が `#filePath` 起点で init の宣言を読み、`name: Type = Type(` / `name: Type = .init(` の形を検出して落とす。例外は理由つきの allowlist に置き、**allowlist が実態から取り残されていないこと**（外した引数のエントリが残り続けないこと）も別テストで見る。

## 検査が実際に効くことの実測

通っただけでは何も検証していないので、4 方向で確かめた。

- `codeFontPreference` に `= CodeFontPreference()` を戻す → 2 テストとも落ちる
- 同じ引数を `= .init()` の形で戻す → 落ちる
- allowlist にある `gitStatusStore` の既定値を外す → 「例外リストに実体のないエントリが残っていない」が落ちる
- **書いた直後に穴が 1 つ見つかった**: 最初の正規表現は `= Type(` しか見ておらず、`= .init()` へ書き換えると素通りした。実測で気づいたのでパターンへ `.init` を追加し、その経緯をテストのコメントに残した

## 検証

- `swift test`: 1714 件全通し（ベースライン 1712 → +2）
- swiftlint: main とのベースライン差分ゼロ（main 54 / HEAD 54、真の新規なし）
- `scripts/check-type-group-size.sh`: exit 0

なお `/review-design` は回していない。新しい状態・述語・表示設定を足さず、値の持ち方も経路も変えない（既存の不変条件を**強める**だけの署名変更）ため、スキルの適用条件に当たらないと判断した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
共有前提の Preference / Store を受け取る init 引数 6 種（両ファイル 9 箇所）からデフォルト値を外し、渡し忘れをコンパイルエラーにした。残した 4 引数は共有インスタンスの受け渡しではなく実装の選択・縮退状態であることを理由つきで記録。この規則は doc コメントに書かれていながら破れたのが本タスクの起点なので、init の宣言をソースから読んで検査する SharedDependencyDefaultsTests を足し、規則を戻す／別の書き方で回避する／例外リストが陳腐化する の 4 方向で実際に落ちることを実測した。swift test 1714 件全通し、swiftlint ベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
