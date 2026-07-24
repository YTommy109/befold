---
id: TASK-116.3
title: テストヘルパーの二重定義を解消する共有ターゲットを新設する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 23:18'
updated_date: '2026-07-24 00:01'
labels:
  - test
  - cleanup
dependencies: []
parent_task_id: TASK-116
priority: medium
ordinal: 30300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befoldCLITests/TestSupport.swift`(本ブランチ新規 +49 行)が `BefoldApp/befoldTests/TestSupport.swift` の一部をソースコピーしており、単一情報源の原則に反している。

## 複製されている実体

- `makeIsolatedDefaults(prefix:)` — CLI 側 L44-49 と GUI 側 L4-9 が**バイト一致**
- `TempDir` — CLI 側 L9-39 と GUI 側 L14-66。init / deinit / `file(named:contents:)` は同一

## 既に発生している乖離と実害

- `symlinkedFile` の既定名が CLI 側 L31 は `"real.md"/"link.md"`、GUI 側 L58 は `"real.mmd"/"link.mmd"`。同名メソッドが片方は Markdown、片方は Mermaid を作る
- CLI 側には `LockedBox` / `waitUntil` / `waitUntilWithRetry` / `file(atPath:)` / `file(named:data:)` が無い
- **その結果として `befoldCLITests/CLIAppLauncherTests.swift:18-23` が `LockedBox` 相当を `nonisolated(unsafe) var` + `DispatchSemaphore` で手組みし、coding_rule.md の「`Sendable` クロージャからの記録・カウントは `LockedBox` を使う。自作は違反」に真正面から抵触している**

複製のコストが仮定ではなく既に実害として現れている。

## 複製理由の再評価

CLI 側 L7-8 は「befoldTests -> befold(GUI 本体) -> BefoldRenderKit の依存グラフを引き込まないため」と説明する。動機自体は正当だが、ソースコピー以外の選択肢が検討された形跡が無い。`TempDir` / `LockedBox` / `makeIsolatedDefaults` / `waitUntil` はいずれも Foundation のみに依存するため、依存ゼロの第 3 ターゲットを立てれば GUI への依存を 1 本も増やさずに単一情報源を保てる。

coding_rule.md の「『現状維持でよい』は代替実装を実際に試して比較した後にのみ許される結論」に従い、この案を実際に試してから複製維持の可否を判断すること。

## ドキュメントのドリフト

`docs/dev/coding_rule.md:79` は `befoldTests/TestSupport.swift = 共有ヘルパー` とだけ書き、L80 の befoldCLITests の説明に 2 つ目の TestSupport の存在が記載されていない。`.claude/CLAUDE.md` のプロジェクト構成ツリーも同様。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 TempDir / LockedBox / makeIsolatedDefaults / waitUntil 系の実体が 1 箇所にのみ存在する
- [x] #2 共有ヘルパーが GUI 本体(befold ターゲット)への依存を持ち込まない
- [x] #3 befoldCLITests から LockedBox が使え、CLIAppLauncherTests の手組みボックスが除去されている
- [x] #4 symlinkedFile の既定拡張子の食い違いが解消されている
- [x] #5 coding_rule.md と .claude/CLAUDE.md のプロジェクト構成が実態と一致している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldApp/BefoldTestSupport/ に依存ゼロの新ターゲット BefoldTestSupport を作る(Foundation のみ)。coding_rule.md の「1 ファイル 1 主要型」に従い 4 ファイルに分割する。
   - TempDir.swift: TempDir(url / file(named:contents:) / file(atPath:contents:) / file(named:data:) / symlinkedFile) と makeHomeTempDir()
   - LockedBox.swift: LockedBox
   - IsolatedDefaults.swift: makeIsolatedDefaults(prefix:)
   - Waiting.swift: testTimeoutSeconds / testTimeout / waitUntil / waitUntilOnMainActor / waitUntilWithRetry / waitUntilWithRetryOnMainActor
   すべて public にする。GUI 本体(befold)や BefoldRenderKit へは一切依存させない。

2. Package.swift に .target(name: "BefoldTestSupport") を追加し、befoldTests / befoldCLITests 双方の dependencies に加える。他ターゲットと同様 SwiftLintBuildToolPlugin を付ける。

3. befoldTests/TestSupport.swift は confirmWatcherArmed(FileWatcher 固有のプローブ)だけを残す。befoldCLITests/TestSupport.swift は全内容が移設先と重複するため削除する。

4. 共有ヘルパーを使う 43 ファイル(befoldTests 40 / befoldCLITests 3)に import BefoldTestSupport を追加する。@_exported import は使わない(アンダースコア付きの非安定属性のため)。

5. symlinkedFile の既定拡張子の食い違い(befoldTests は real.mmd/link.mmd、befoldCLITests は real.md/link.md)を .mmd に統一する。呼び出し 5 箇所すべてが既定値を使っており、唯一 .md 側だった CLICheckAndBookmarkDefaultsTests:28 はシンボリックリンクの実体パス正規化のみを検証していて拡張子に依存しないことをソースで確認済み。TempDir の既定 prefix も befold-test に統一する。

6. CLIAppLauncherTests.swift:18-23 の手組みボックス(nonisolated(unsafe) var + DispatchSemaphore)を LockedBox に置き換える。複製の実害として現れていた規約違反の解消がこのタスクの主目的のひとつ。

7. docs/dev/coding_rule.md と .claude/CLAUDE.md のプロジェクト構成ツリーに BefoldTestSupport を追記し、TestSupport が 2 つある旨の記述ずれを直す。

8. 検証: swift test を完走させ、befoldCLITests 単独実行も確認する。GUI 依存が混入していないことは Package.swift の dependencies で担保する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
計画ステップ 6(CLIAppLauncherTests の手組みボックスを LockedBox へ置換)は、TASK-116.1 で captureStderr ごと削除した時点で既に解消されていた。grep で befoldCLITests に nonisolated(unsafe) / DispatchSemaphore / NSLock が残っていないことを確認済み。よって本タスクでの作業は不要。ただし「複製により CLI 側に LockedBox が無いこと」自体は残っているため、共有ターゲット化(ステップ 1〜4)は引き続き必要。

実装: BefoldApp/BefoldTestSupport/ に依存ゼロの新ターゲットを作り、TempDir.swift / LockedBox.swift / IsolatedDefaults.swift / Waiting.swift の 4 ファイルに分割した。befoldCLITests/TestSupport.swift は全内容が重複するため削除。befoldTests/TestSupport.swift は FileWatcher 固有の confirmWatcherArmed だけを残した。共有ヘルパーを使う 41 ファイルに import BefoldTestSupport を追加し、SwiftFormat で import 順を整えた。@_exported import はアンダースコア付きの非安定属性のため使っていない。

検証:
- AC#1(単一情報源): grep で TempDir / LockedBox / makeIsolatedDefaults / waitUntil の定義が befoldTests・befoldCLITests に残っていないことを確認。TestClock.swift の waitUntilYielding のみ残るが、これは仮想クロック専用の別ヘルパーで共有対象ではない。
- AC#2(GUI 非依存): BefoldTestSupport/*.swift の import は Foundation のみ。Package.swift の当該ターゲットに dependencies: の宣言自体が無く、befold / BefoldRenderKit への依存経路が存在しない。
- AC#3(LockedBox が CLI 側から使える / 手組みボックス除去): befoldCLITests の dependencies に BefoldTestSupport を追加済みで、同ターゲットの全テストがビルド・pass する。手組みボックス(nonisolated(unsafe) var + DispatchSemaphore)は TASK-116.1 で captureStderr ごと除去済みで、grep でも befoldCLITests に NSLock / DispatchSemaphore / nonisolated(unsafe) が残っていないことを確認。
- AC#4(symlinkedFile の既定拡張子): .mmd に統一。唯一 .md 側だった CLICheckAndBookmarkDefaultsTests の symlink テストを含め全テストが pass。TempDir の既定 prefix も befold-test に統一した。
- 全体: swift test が 601 tests / 76 suites を 14.870 秒で pass。befoldCLITests 単独でも 47 tests / 5 suites が 0.142 秒で pass。

AC#5(ドキュメント同期)はブロック中。docs/dev/coding_rule.md と .claude/CLAUDE.md のプロジェクト構成ツリーには、本作業とは無関係な未コミット変更(CLI バイナリ分離のアーキテクチャ記述追加)が入っており、しかも書き換えるべき行(befoldTests / befoldCLITests の行)が同一 diff ハンクの中にある。ユーザーから「未コミット変更はそのまま触らない」方針の指示を受けているため、分離してコミットできない。扱いをユーザーに確認する。

AC#5: ユーザー承認のもと、未コミットのまま残っていた CLI バイナリ分離分の記述と BefoldTestSupport の追記を 1 コミット(3b2ed81)にまとめた。構成ツリーの同一ハンクに重なるため分離不可という事情はコミットメッセージに明記した。あわせて coding_rule.md の「共有テストヘルパー(TestSupport.swift)」節を「共有テストヘルパー(BefoldTestSupport)」へ改め、Foundation のみに依存を保つ制約と import BefoldTestSupport の書き方を追記した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
依存ゼロの BefoldTestSupport ターゲットを新設し、befoldTests と befoldCLITests に二重定義されていた TempDir / makeIsolatedDefaults を単一情報源へ集約した。LockedBox / waitUntil 系も同ターゲットへ移し、共有ヘルパーを使う 41 ファイルに import BefoldTestSupport を追加した。

複製理由として挙げられていた「befoldTests → befold(GUI 本体) → BefoldRenderKit の依存グラフを引き込みたくない」という懸念は、依存ゼロの第 3 ターゲットを実際に作ることで解消できることを確認した(import は Foundation のみ、dependencies の宣言自体が無い)。これは規約の「現状維持は代替実装を試した後にのみ許される結論」に沿った検証。

複製の実害だった「CLI 側に LockedBox が無いため手組みしていた」箇所は TASK-116.1 で captureStderr ごと除去済みで、本タスクでは CLI 側から LockedBox を使える状態を整えた。symlinkedFile の既定拡張子の食い違い(.mmd / .md)は .mmd に統一し、唯一 .md 側だったテストが拡張子に依存しないことをソースで確認した。

検証: swift test が 601 tests / 76 suites を 14.870 秒で pass。befoldCLITests 単独でも 47 tests / 5 suites が 0.142 秒で pass。SwiftFormat --lint は全ターゲットでクリーン。ドキュメントは coding_rule.md と .claude/CLAUDE.md の構成ツリー・共有ヘルパー節を実態に同期した。
<!-- SECTION:FINAL_SUMMARY:END -->
