---
id: TASK-439
title: project.yml に BefoldTestSupport ターゲットが無く、Xcode 側のテスト経路に載っていない
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 15:08'
updated_date: '2026-08-11 23:29'
labels:
  - ci
dependencies: []
priority: medium
type: task
ordinal: 672000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435 の調査中に判明した既存のずれ。TASK-435 とは独立に存在する。

`BefoldApp/Package.swift` は `BefoldTestSupport` を独立ターゲットとして定義し、`befoldTests` / `befoldCLITests` の双方が dependencies に列挙している（Package.swift:91-107）。一方 `BefoldApp/project.yml` には **`BefoldTestSupport` の記述が 1 件も無い**（`grep -n BefoldTestSupport BefoldApp/project.yml` が 0 件）。`befoldTests` ターゲットの dependencies も `befold` / `BefoldKit` / `BefoldRenderKit` の 3 つだけ（project.yml:159-171）。

## 影響（未確認を含む）

`BefoldTestSupport/GitTestRepo.swift` を使うテスト（`GitCommandRunnerTests` / `GitStatusReaderIntegrationTests` / `GitDiffReaderIntegrationTests` / `GitRepositoryIntegrationTests` の計 43 本）が、`swift test` では実行される一方、Xcode 側（`xcodebuild test`）でどう扱われているかが未確認。次のいずれかのはず。

- そもそも `.xcodeproj` の befoldTests にソースが含まれずビルドから落ちている
- 何らかの経路で拾われている

**着手時にまず `xcodegen generate` した `.xcodeproj` の befoldTests のソース一覧を実測して、どちらかを確定させること。**

## なぜ今起票するか

TASK-435.1 の設計レビューで、新しいテストフィクスチャを `BefoldTestSupport` に置くと同じずれに載ってしまうことが分かった。435.1 側は `befoldTests` へ置いて回避するが、ずれ自体は残るため独立して扱う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 xcodegen が生成する .xcodeproj で befoldTests が BefoldTestSupport のソースをどう扱っているかが実測で確定している
- [x] #2 Package.swift と project.yml のターゲット構成のずれが解消されている（project.yml へ追加するか、ずれてよい理由が記録されている）
- [x] #3 CI で実際に走るテスト集合が swift test と xcodebuild test で一致することが確認されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## AC#1 実測（Xcode 側の扱いの確定）

xcodegen generate 済みの .xcodeproj に対し `xcodebuild build-for-testing -scheme befold` を実行 → **exit 65 / `error: unable to resolve module dependency: 'BefoldTestSupport'`**。befoldTests ターゲットが**丸ごとビルドできていなかった**（一部のテストが落ちていたのではない）。befoldTests の 111 ファイルが `import BefoldTestSupport` している。pbxproj 内の BefoldTestSupport 参照は 0 件だった。

## AC#2 ずれの解消

- project.yml に `BefoldTestSupport` を **library.static** で追加し、befoldTests の dependencies に加えた。
  - framework で試すと xctest 内へ埋め込まれて署名対象になり `bundle format unrecognized` で失敗した（Info.plist を持たないため）。Package.swift 側も `.target`（静的）なので静的ライブラリに合わせた。
  - `Testing`(swift-testing) はテスト用フレームワーク検索パス配下にあり通常ターゲットからは解決できない（`Unable to resolve module dependency: 'Testing'`）。**ENABLE_TESTING_SEARCH_PATHS: true** で解決した。
- `befoldCLITests` は project.yml に載せない**意図的なずれ**として確定（ユーザー判断）。8 ファイルが `@testable import befold_cli` で実行ファイルターゲットの中身に触るためテストホストが要るが、**Xcode は plain tool を TEST_HOST として受け付けない**（実測: バイナリが実在していても `Could not find test host for befoldCLITests` でスキーム構築時に失敗。スキームのビルド対象へ befold-cli を足しても同じ）。理由は project.yml のコメントに記録し、構造変更は **TASK-456** として起票した。
- ずれが再発したら落ちるように `befoldTests/PackageProjectTargetParityTests.swift` を追加。Package.swift と project.yml のターゲット集合を突き合わせ、許容する差（project.yml のみ: BefoldQuickLook / Package.swift のみ: befoldCLITests）以外を失敗させる。**許容集合を空にすると実際に落ちることを実行して確認済み**。

## AC#3 テスト集合の一致

- `swift test` → 1431 tests / 212 suites passed
- `xcodebuild test -scheme befold` → 1359 tests / 198 suites passed
- 差分 72 tests / 14 suites は befoldCLITests ちょうど（befoldCLITests のファイル数 14 = suite 数 14）。上記の意図的なずれと一致し、それ以外の取りこぼしは無い。
- **CI で実際に走るのは `swift test` のみ**（.github/workflows/ci.yml に xcodebuild の記述は 0 件、テスト実行は 141 行目 `swift test` と 233 行目 `swift test --sanitize=thread`）。したがって CI のテスト集合は今回の変更前後で変わらない。

## 併せて修正

`IsolatedDefaultsTests.doesNotWriteToTheSharedSuite` が xcodebuild 経路でのみ失敗した。テストホストが befold.app 自身のため `UserDefaults(suiteName: \"com.degino.befold\")` が nil を返す（自分の bundle identifier は suite 名にできない）。その場合の共有スイートの実体は standard なのでフォールバックさせた（standard への漏れは元から後続の #expect が見ている）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
project.yml に BefoldTestSupport（library.static + ENABLE_TESTING_SEARCH_PATHS）を追加し、befoldTests の dependencies に接続した。これにより Xcode 経路で丸ごとビルド不能だった befoldTests が実行できるようになった（実測: 変更前 build-for-testing が unable to resolve module dependency で exit 65 → 変更後 xcodebuild test が 1359 tests passed）。befoldCLITests は Xcode が plain tool を TEST_HOST として受け付けないため意図的なずれとして残し、理由を project.yml へ記録・構造変更を TASK-456 に起票した。ずれの再発は PackageProjectTargetParityTests が検出する（許容集合を崩すと落ちることを確認済み）。swift test 1431 / xcodebuild test 1359 の差 72 tests は befoldCLITests ちょうどで、CI は swift test のみを実行するため CI のテスト集合に変化はない。
<!-- SECTION:FINAL_SUMMARY:END -->
