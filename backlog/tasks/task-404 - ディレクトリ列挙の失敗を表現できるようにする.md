---
id: TASK-404
title: ディレクトリ列挙の失敗を表現できるようにする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 03:09'
updated_date: '2026-08-10 07:06'
labels: []
dependencies: []
priority: low
type: task
ordinal: 661000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`DirectoryEnumeration.sortedContents` は列挙の失敗を `try?` で握り潰し、空の組を返す（doc に「列挙に失敗した場合は空の組を返す」と明記）。`DirectoryLister.listEntriesAsync` / `childEntriesAsync` も throws でも Optional でもない。

このため呼び出し側は「空のフォルダ」と「列挙失敗（権限が無い・消えた）」を区別できない。

## いつ困るか

TASK-361.3 でサイドバーのツリー展開の子リスト状態を設計した際、`.failed` を置こうとしたが**到達不能**になるため落とした（到達不能な状態を型に置くと「`.failed` が来ない = 失敗が無い」と読めてしまう）。結果、権限の無いフォルダを展開すると「空のフォルダ」として表示される。

## 波及範囲

`sortedContents` の消費側は GUI（DirectoryLister）と CLI（SupportedFileResolver 経由）の両方にあるため、失敗を表現できる形（Result / Optional）へ変えると全消費側に波及する。361.3 のスコープには含めなかった。

## 参考

- `BefoldApp/BefoldKit/.../DirectoryEnumeration.swift`
- `BefoldApp/befold/App/SidebarExpansion.swift` の `Children` の doc（この判断の記録）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 列挙失敗と「空のディレクトリ」が呼び出し側で区別できる
- [x] #2 GUI・CLI 双方の消費側が新しい形へ追従している
- [x] #3 サイドバーのツリー展開が、列挙失敗を「空のフォルダ」として表示しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 単純化の検討（先に実施）

失敗を「表示直前に別途 isReadable を叩いて判定する」案は採らない。判定の置き場所が
列挙結果と別になり、CLAUDE.md の「同型のバグは判定の置き場所を内部状態へ移す」と逆行する。
列挙の戻り値そのものに失敗を載せる（Optional）のが単一情報源を保つ最小形。

新しい状態は 2 つだけ増やす（Children.failed / SidebarDisclosureState.expandedFailed）。
どちらも既存の「空 != 未到着」の区別（TASK-285 と同型）と同じ列に並ぶもので、
これ以上の抽象（Result + Error 型）は消費側が誰も理由を読まないため導入しない。

## 実装手順

### BefoldKit（失敗を表現できる形へ）
1. DirectoryEnumeration.sortedContents を Optional 戻り（nil = 列挙失敗）にし、doc の
   「失敗時は空の組を返す」を書き換える。
2. sortedFiles も Optional 戻りにする。
3. firstSupportedFile は guard let で nil へ畳む（doc に「この関数の呼び出し側は
   失敗と空フォルダを区別する必要が無い」理由を書く）。
4. SupportedFileResolver.resolveFileToOpen も同様に明示的に畳む（CLI 側の追従）。

### GUI（ツリー展開が失敗を空フォルダとして見せない）
5. DirectoryLister の private sortedContents ラッパを Optional 素通しにする。
6. childEntries / childEntriesAsync を [FileListEntry]? に変える（nil = 列挙失敗）。
7. buildEntries（ルート一覧）は ?? [] で明示的に畳む。理由を doc に書く
   （ルート列挙失敗の表示は本タスクのスコープ外。AC はツリー展開のみ）。
8. SidebarExpansion.Children に .failed を追加。apply(_ entries: [FileListEntry]?, for:)
   の nil を .failed にし、着地時の一致確認は従来どおり 1 箇所に閉じる。
   型 doc の「.failed は到達不能なので置かない」の Note を書き換える。
9. SidebarExpansion.Material に failed: Set<String> を追加（expanded / loading と互いに素）。
10. SidebarRowBuilder.rows に failed を渡し、行は増やさない（並べる子が無い）。
11. SidebarDisclosureState に .expandedFailed を追加。SidebarDisclosure.state に
    didFail を **必須引数** で足す（デフォルト引数にすると渡し忘れが静かに通る）。
12. FileListEntryRow に .expandedFailed の見た目（exclamationmark.triangle）と
    help 文字列を足す。Localizable.xcstrings へ 1 件追加（キー順ソートはしない）。
13. SidebarDisclosureResolver は .expanded のみを触るので変更不要。回帰テストで固定する。

### テスト
- DirectoryEnumerationTests: 既存の sortedContentsReturnsEmptyForMissingDirectory を
  「nil を返す」へ書き換え、空ディレクトリが ([], []) を返すことと対で固定する。
- SidebarDisclosureTests: 失敗 / 空フォルダ / 未到着 / 絞り込み 0 の 4 つが別状態であること。
- SidebarExpansionTests: apply(nil) が .failed になり、世代・epoch ガードが失敗にも効くこと。
- SidebarRowBuilderTests: 失敗フォルダが行を増やさず .expandedFailed になること。
- DirectoryLister: 読めないディレクトリで childEntries が nil、空ディレクトリで [] になること。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## /review-design の結果（実装前）

独立レビューで 9 項目を通し、実装方針を変える指摘 5 件を採用した。

1. **material の列挙漏れ**（項目 1・9）: 現在の `guard case let .loaded ... else { loading.insert }`（SidebarExpansion.swift:60-67）は .failed を `loading` に落とし、権限の無いフォルダが永久スピナーになる。**default を置かない exhaustive switch** へ書き換え、ケース追加がコンパイルエラーになる形にする。
2. **disclosure に failed が届かない**（項目 3・4）: SidebarRowBuilder.swift:93 の `isExpanded: expanded.contains || loading.contains` に failed を含めないと .collapsed に落ち、表示だけでなく **→ キーが expand を出して beginExpanding が nil を返し無反応**になる（SidebarKeyAction.swift:43-46 で確認）。Flattening へ failed を渡す。SidebarDisclosure.state の適用順は isExpanded → didFail → loadedChildCount → 件数 に固定する。
3. **.failed からの復帰経路が無い**: beginExpanding が expandedKeys の membership だけで早期 return するため、失敗後は再展開しても再試行されない。**children[key] が .failed のときだけ再試行を許す**。invalidateChildren 経由の自動再試行はテストで固定する。
4. **計画が挙げ漏らした sortedContents 消費側**: allEntriesSorted（Quick Open）/ containsSupportedFile / FolderListingView / CLI 文言。畳み方をその場の `?? ([], [])` で決めず、理由を doc に書く。
5. **失敗を注入できない**（項目 7）: 列挙は FileManager.default 固定で FileReading は分類にしか使われないため、失敗ブランチは決定的にモックできない。**存在しないディレクトリ**で測るのを主とし、権限テストは `.enabled(if: getuid() != 0)` で root 実行時にスキップ記録が残る形にする。

## 決めたこと（記録）

- CLI（CLICheckCommand.swift:23 の "No file found in folder"）の文言は**変えない**。列挙失敗と空フォルダで案内を分けるのは別タスク。本タスクでは resolveFileToOpen で明示的に nil へ畳み、理由を doc に残すところまで。
- ルート列挙（buildEntries / listEntriesAsync）の失敗は `?? []` へ明示的に畳む。FolderListingView.cachedEntries が既に持つ「nil = 未到着 / [] = 空」の区別へ失敗を [] として流すことになるため、**後続タスクの Acceptance Criteria として起票する**（doc コメントでの申し送りにしない）。
- SidebarKeyAction.Target(entry:) では .expandedFailed を isExpanded = true とする（← で畳める / → で無反応にしない）。

## 検証（実測）

- `swift test --skip Integration --skip FileWatcherTests`: **1258 tests / 174 suites passed**（EXIT=0）。除外条件はこのリポジトリの PostToolUse フックと同じ。
- 新規テスト 12 件はすべて通過。うち本番経路の配線を測るのは `SidebarNavigatorExpansionTests.failedChildListingSurfacesOnRow`（childrenLister が nil を返すと、その行の disclosure が .expandedFailed になり、行は増えない）。
- `ViewerRendererZoomIntegrationTests` の 3 件はフルラン時に 20 秒の `isReady → false` で落ちたが、**単独実行では本ブランチでも 0.36 秒で通過**（origin/main を別ディレクトリへ展開した比較でも同じ）。WKWebView の準備がフルランの並列実行で間に合わないもので、本変更とは無関係。
- swiftlint: HEAD コミット時点を `git archive HEAD` で別ディレクトリへ展開して測り、**ベースライン差分ゼロ**。途中で出た 4 件（is_disjoint ×3 / DirectoryListerTests の file_length 421 行）は閾値を緩めず、`isDisjoint(with:)` への書き換えと `DirectoryListerEnumerationFailureTests` への分割で解消した。
- swiftformat: 私が触った範囲は 0 件。`FileListEntry.swift` の redundantEquatable は**着手前から作業ツリーにあった未コミット変更**によるもので、本タスクでは触っていない。

## AC の裏付け

- AC#1: `DirectoryEnumerationTests.sortedContentsReturnsNilForMissingDirectory` が「失敗 = nil」と「空ディレクトリ = 空の組」を対で固定。権限のケースは `.enabled(if: getuid() != 0)` 付きで別テスト。
- AC#2: GUI は childEntries → SidebarExpansion.failed → SidebarRowBuilder → .expandedFailed まで配線しテストで固定。CLI は SupportedFileResolver で明示的に nil へ畳み、理由を doc に記載（文言は変更しないと決定）。
- AC#3: `SidebarRowBuilderTests.failedFolderShowsFailureWithoutAddingRows` と `SidebarDisclosureTests.failureIsDistinctFromLoadingAndEmpty` が、失敗が .expandedEmpty にも .loadingChildren にも .collapsed にも落ちないことを固定。

## 残した申し送り

ルート一覧 / プレビュー / Quick Open の 3 経路は失敗を明示的に空へ畳んだ。**TASK-410 の Acceptance Criteria として起票済み**（doc コメントだけの申し送りにしていない）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DirectoryEnumeration.sortedContents を Optional 戻りにして「列挙失敗」と「空のフォルダ」を型で区別できるようにし、サイドバーのツリー展開が権限の無いフォルダを空フォルダとして表示しないようにした。

失敗は SidebarExpansion.Children.failed → Material.failed → SidebarRowBuilder → SidebarDisclosureState.expandedFailed と伝わり、行を増やさずに警告記号で示す。実装前に /review-design を回して 5 件の設計指摘を反映した: material の guard-else を exhaustive switch にして列挙漏れがコンパイルエラーになる形にし、failed を disclosure 判定へ配線しないと .collapsed に落ちて → キーが無反応になる穴を塞ぎ、失敗したフォルダだけ畳まずに再展開して取り直せるようにした。区別を必要としない消費側（firstSupportedFile / SupportedFileResolver / ルート一覧 / Quick Open）は、その場で明示的に畳んで理由を doc に残した。

検証: swift test 1258 件通過、swiftlint ベースライン差分ゼロ、新規テスト 12 件（本番経路の配線テストを含む）。
<!-- SECTION:FINAL_SUMMARY:END -->
