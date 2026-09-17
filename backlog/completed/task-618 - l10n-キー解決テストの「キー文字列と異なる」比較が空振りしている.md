---
id: TASK-618
title: l10n キー解決テストの「キー文字列と異なる」比較が空振りしている
status: Done
assignee:
  - '@claude'
created_date: '2026-09-12 14:24'
updated_date: '2026-09-15 08:14'
labels:
  - test
dependencies: []
priority: low
type: bug
ordinal: 808000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarEmptyStateTests（resolvesTitleForEveryReason / resolvesDescriptionForFilteredReasons）と BookmarkManagerPromptTests.resolvesEveryKey は、キーが Localizable.xcstrings に無いことを検知するつもりで `#expect(text != String(describing: key))` を置いている。しかし `String(describing:)` を `String.LocalizationValue` に掛けると `LocalizationValue(arguments: [], key: "...")` という説明文が返る（TASK-536.4 の責務レビューで scratchpad の swiftc 実行により実測）。`String(localized:)` が未解決時に返すのは素のキー文字列なので、この比較は常に真で、キーの足し忘れを検知しない。直前の `!text.isEmpty` だけが効いている。

3 箇所が同型なので一度に直す。候補: 未解決時の値そのものを比較相手にする（例: 存在しないテーブルを指定した `String(localized: key, table: "__missing__", bundle: .l10n)` はキー文字列を返すはず。未確認なので、まず 1 本を swift test で確かめてから 3 箇所へ展開する）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 SidebarEmptyStateTests の 2 本と BookmarkManagerPromptTests の 1 本が、xcstrings に無いキーを渡すと落ちることを実測してから書き換える（一時的にキーを消して落ちることを確認）
- [x] #2 3 箇所とも同じ比較の書き方に揃え、判定の根拠（未解決時に何が返るか）をテストの doc コメントに残す
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
5. 実装中に判明: タスク説明が提案する「存在しないテーブルを指定する」案は使えない(下記 Notes)。既存の LocalizationTests.swift のカタログ直読みパターンへ合わせる方針に変更した
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 前提の訂正(実装中に判明、実測: 2026-09-15)

タスク説明が候補として挙げていた「存在しないテーブルを指定した `String(localized: key, table: "__missing__", bundle: .l10n)` はキー文字列を返すはず」という案は**成立しない**。実測(BefoldApp/befoldTests に一時テストを置き `swift test --filter` で確認、後で削除):

- `swift test`(SwiftPM)では `.xcstrings` は `.process()` されても String Catalog コンパイラを通らず、生の JSON のままバンドルへコピーされるだけ(`swift build --product befold` のログで実際に "Copying Localizable.xcstrings" とだけ出ることを確認、.lproj は作られない)。
- そのため `String(localized: key, bundle: .l10n)` は **キーが実在していても** 常にキー文字列をそのまま返す(実測: `sidebar.empty.bothFilters` は en 訳 "No Matching Changed Files" を持つが、`swift test` では "sidebar.empty.bothFilters" が返る)。テーブル名を変えても同じキー文字列が返るだけで、実在キーと欠落キーを区別できない。
- これは本タスク固有の問題ではなく、**このプロジェクトで既知・既定の制約**(`LocalizationTests.swift:8-10` の doc コメント、TASK-503 / TASK-507 / TASK-94.3 / SidebarContextMenu.swift / HelpShortcutSections.swift に前例あり)。CI の `swift test` ジョブも同じ制約下にある。

## 採った方針(単純化検討: 既存パターンの再利用)

新しい比較方式を発明せず、**既存の `LocalizationTests.swift` が採っているカタログ直読み方式に 3 箇所を揃えた**。`shortcutCatalogKeysAreTranslated()` と全く同じ判定(カタログにキーが実在し、en/ja とも訳が空でない)を使う。

- `LocalizationTests.swift` のカタログ読み取り(`loadCatalog`/`parseStringCatalog`/`loadCompiledStrings`)を `BefoldTestSupport/LocalizableCatalog.swift` へ抽出し、3 ファイルから共有する(3 箇所以上で同じ定型を書く手組みを避ける、`docs/dev/rules/testing.md` の共有ヘルパー規約に合わせた)。`LocalizationTests.swift` 側は抽出した `LocalizableCatalog.load(bundle:)` を呼ぶだけになり、177→135 行に縮んだ。
- `SidebarEmptyReason.titleKey` 等は `String.LocalizationValue`(公開 API でキー文字列を取り出せない)なので、テストからカタログを引くために `Mirror(reflecting:)` でキー文字列を取り出す `String.LocalizationValue.rawKeyForTesting`(test-only extension、`BefoldTestSupport`)を追加した。実測: Swift 6.3.3 で `key` ラベルの子要素として取れることを確認済み(`BefoldCLIOptionValidationTests` に `Mirror(reflecting:)` の前例あり)。private な内部表現に依存するため、Swift のバージョンが上がったら再確認が要ることをコメントに明記した。
- 本体側(`SidebarEmptyState.swift` / `BookmarkManagerPrompt.swift`)は無変更。

## AC #1 の実測(2026-09-15)

3 テストそれぞれについて、対象キーを `Localizable.xcstrings` から一時的に削除して `swift test --filter` し、失敗することを確認してから `git checkout --` で復元した(コミットには含まれない一時操作)。

- `SidebarEmptyStateTests.resolvesTitleForEveryReason`: `sidebar.empty.bothFilters` を削除 → 失敗(「キー sidebar.empty.bothFilters に en の訳がありません」)。復元後は 15/15 pass
- `SidebarEmptyStateTests.resolvesDescriptionForFilteredReasons`: `sidebar.empty.bothFilters.description` を削除 → 失敗(ja/en 両方)。復元後は pass
- `BookmarkManagerPromptTests.resolvesEveryKey`: `bookmarks.manager.setAlias.title` を削除 → 失敗。復元後は pass

## 検証

- `swift test --filter "SidebarEmptyStateTests|BookmarkManagerPromptTests|LocalizationTests"`: 22/22 pass
- `swift test`(全体、Integration/FileWatcherTests 除く): 1942 件中 10 件失敗。**この 10 件は本タスクと無関係の既存失敗**(PDFSurfacePositionTests / PDFSurfacePageIndexTests / PDFPageIndicatorModelTests、PDF のスクロール位置・ページ番号計算)。`git stash`(タグ付き、apply→drop で復元)で本変更を退避し同フィルタで再実行 → 同じ 10 件が同じ内容で失敗することを確認済み。本タスクの変更前から存在する回帰で、本タスクの範囲外
- `swift build` / `xcodegen generate` 後の `xcodebuild build -scheme befold`: 両方成功(新規ファイル `LocalizableCatalog.swift` を追加したため両方を確認)
- `swift package plugin swiftformat -- --lint`: 全ファイル整形済み
- swiftlint ベースライン差分(`/swiftlint-baseline`、main は `git archive` で別ディレクトリに展開): 46 件 vs main 48 件。真の新規 0 件、解消 2 件(`LocalizationTests.swift` にあった `Nesting Violation` が、抽出先の `LocalizableCatalog.swift` で型を 1 段減らして解消。関数ローカルの 4 段ネスト struct を、`Entry` だけ `CatalogFile` に残し `Localization`/`StringUnit` を private top-level 型へ出す形にした)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
l10n キー解決テスト 3 本(SidebarEmptyStateTests 2 本 / BookmarkManagerPromptTests 1 本)の常に真になる比較(String(localized:) の戻り値と String(describing:) の比較)を、Localizable.xcstrings を直接読むカタログ突き合わせへ書き換えた。実装中に判明した重要な前提訂正: タスクが提案していた「存在しないテーブルを指定する」案は swift test 環境では成立しない(String Catalog がコンパイルされず String(localized:) は実在キーでも常にキー文字列を返すため)。既存の LocalizationTests.swift が採っている「カタログ直読み」方式に揃え、その読み取りロジックを BefoldTestSupport/LocalizableCatalog.swift へ抽出して 3 ファイルで共有した。String.LocalizationValue から生のキー文字列を取り出す rawKeyForTesting(Mirror ベース、test-only)を追加。3 テストとも、対象キーを一時的に削除して失敗することを実測してから復元した(AC#1)。判定根拠は 3 箇所とも同じ doc コメントで説明している(AC#2)。swift build・xcodebuild・swiftformat・swiftlint ベースライン(真の新規 0、解消 2)・関連 swift test 22 件はすべてクリーン。swift test 全体で 10 件の失敗が残るが、変更前の main でも同じ 10 件(PDF 面のスクロール/ページ番号計算、無関係)が失敗することを stash で確認済みで、本タスクの範囲外。
<!-- SECTION:FINAL_SUMMARY:END -->
