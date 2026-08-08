---
id: TASK-315.1
title: ソース表示中のファイルの git 差分本文を取得する経路を作る
status: Done
assignee:
  - '@claude'
created_date: '2026-08-05 14:46'
updated_date: '2026-08-05 15:05'
labels: []
dependencies: []
parent_task_id: TASK-315
priority: medium
type: task
ordinal: 514000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 の 1 段目。差分の描画には手を付けず、Swift 側で「表示中のファイルの unified diff を取得して WebView 層まで届ける」経路だけを作る。

現状、差分本文を取る実装は無い。git 実行は `GitCommandRunner`（`BefoldApp/befold/App/GitCommandRunner.swift:105`）に一元化されており任意の引数を渡せるため、コマンド追加自体は容易。既存 8 コマンドはすべてメタデータのみで、`git diff` も `--name-status` でパス名しか取っていない（`GitStatusReader.swift:100-102`）。

制約:

- git 実行はメインアクター外が契約（`GitStatusReader.swift:26-29`）。既存の `GitStatusStore` は detached + inFlight 畳み込み + `.git/index` fingerprint キャッシュ（`GitStatusStore.swift:39-121`）で、同じ枠組みに乗せるか、乗せない理由を残す
- `GitCommandOutcome` は `.output` / `.rejected`（確定した答え）/ `.unavailable`（不明、キャッシュ禁止）の三値
- QuickLook 拡張（appex）では git を叩かない
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 表示中のファイルの unified diff を取得できる（比較対象の決定と、その根拠が実装ノートに記録されている）
- [x] #2 未追跡・バイナリ・差分なし・git 管理外のそれぞれで、呼び出し側が区別できる結果が返る
- [x] #3 git 実行がメインアクター外で行われ、タイムアウト・.unavailable がキャッシュされない
- [x] #4 QuickLook 拡張の描画経路では差分取得が行われない
- [x] #5 上記がユニットテストで検証されている（実 git リポジトリを使うテストを含む）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 型を追加する: GitFileDiff（diff(String) / noChanges / untracked / binary / tooLarge / noCommits / notInRepository）と protocol GitDiffReading（nil = .unavailable、キャッシュ禁止）
2. GitDiffReader を実装する。比較対象は HEAD（`git --no-optional-locks diff --no-color --no-ext-diff -U3 HEAD -- <path>`）。空出力のときだけ `ls-files --error-unmatch` で未追跡かを判定し、rejected のときだけ `rev-parse --git-dir` で「リポジトリ外」と「HEAD 無し」を分ける
3. GitDiffLoader（@MainActor、Task.detached + inFlight 畳み込み、キャッシュなし）を追加する
4. テスト: 実 git リポジトリを作る GitDiffReaderTests（通常/ステージ済み含む/未追跡/バイナリ/変更なし/コミット前/リポジトリ外/サイズ上限）と、スタブ reader での GitDiffLoaderTests（重複要求の畳み込み・キャッシュしないこと）
5. xcodegen generate → swift test → swiftformat --lint → swiftlint ベースライン差分
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 着手前の設計レビュー（/review-design）

チェックリストを当てて 2 点を設計に反映した。

- **判定の真実の源**: `git diff HEAD -- <path>` の出力が空でも「変更なし」とは限らない（未追跡でも空、初回コミット前は exit 128）。空だったときだけ `ls-files --error-unmatch` で追跡有無を、rejected だったときだけ `rev-parse --git-dir` でリポジトリ内外を、それぞれ事実で判定する
- **ライフサイクル・高頻度経路**: 作業ツリーの編集は `.git/index` を動かさないため、GitStatusStore の fingerprint キャッシュ方式を流用すると差分が陳腐化する。よって**キャッシュしない**（重複要求の畳み込みだけ行う）。保存のたびに走るため、出力サイズ上限（1 MiB）を設けて巨大差分で描画を詰まらせない

## git 挙動の実測（2026-08-05、一時リポジトリ）

| ケース | 出力 | 終了コード |
|---|---|---|
| HEAD 無しで `diff HEAD` | `fatal: bad revision 'HEAD'` | 128 |
| 通常の変更 | unified diff | 0 |
| 未追跡ファイル | 空 | 0 |
| バイナリ | ヘッダ + `Binary files a/… and b/… differ`（@@ 無し） | 0 |
| ステージ済み + 未ステージ | 両方が 1 つの diff に出る | 0 |
| `ls-files --error-unmatch`（追跡済み/未追跡） | — | 0 / 1 |
| リポジトリ外 | — | 1 |
| `--no-optional-locks` と `diff` の併用 | 可 | 0 |

**比較対象を HEAD にした根拠**: ビューアが表示しているのは作業ツリーの内容で、ユーザーが見たいのは「最後のコミットから何を変えたか」。`git diff`（index 比較）だとステージ済みの変更が差分から消え、サイドバーのバッジが変更ありを示しているのに差分が空という食い違いが起きる。実測でも HEAD 比較ならステージ済み・未ステージの両方が 1 つの diff に出る。

## AC#4（QuickLook では差分取得しない）の担保

`project.yml:83-90` のとおり BefoldQuickLook の sources は `BefoldQuickLook/` のみで、依存は BefoldKit と BefoldRenderKit だけ。git 実行系（GitCommandRunner ほか）は app ターゲット `befold/App/` にあり appex にコンパイルされない。新しい GitDiffReader も同じ場所に置くことで、構造的に呼べない。

## 実装（2026-08-06）

- `befold/App/GitFileDiff.swift`: 取得結果を 7 状態の列挙で返す（diff / noChanges / untracked / binary / tooLarge / noCommits / notInRepository）。「本文が無い」理由ごとに表示が変わるため、空文字列 1 つに潰さない
- `befold/App/GitDiffReader.swift`: `git --no-optional-locks diff --no-color --no-ext-diff -U3 HEAD -- <path>`。空出力のときだけ `ls-files --error-unmatch` で追跡有無を確認し、rejected のときだけ `rev-parse --git-dir` でリポジトリ外とコミット前を分ける。UTF-8 として読めない出力と `Binary files ` 行はバイナリ扱い。上限 1 MiB
- `befold/App/GitDiffLoader.swift`: @MainActor、`Task.detached(priority: .utility)` で実行し、(ルート, ファイル) 単位で走行中要求へ相乗り。**キャッシュしない**

## 検証

- `swift test` 1136 tests green（新規 14 件を含む）
- **テストが空振りしていないことを確認**: `data.isEmpty` の分岐を `.noChanges` 固定へ壊すと「未追跡ファイルは untracked」だけが落ちる（`Expectation failed: (result → .noChanges) == .untracked`）。戻して再度 green
- swiftformat `--lint`: 全 8 ターゲットで 0 件
- swiftlint: 全体 78 件で、新規 3 ファイルに対する指摘は 0 件（既存ファイルは未変更のためベースライン差分ゼロ）
- AC#4 は構造で担保: `project.yml:83-90` のとおり BefoldQuickLook の sources は `BefoldQuickLook/` のみで、新規 3 ファイルを置いた `befold/App/` は appex にコンパイルされない

## 次段への申し送り

`GitDiffLoader` はまだ誰からも呼ばれていない（描画が無いため）。ViewerStore への配線は TASK-315.2 で、差分の適用時にファイル URL の一致を確認して世代競合を防ぐこと。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
表示中ファイルの unified diff を取得する経路を追加した。比較対象は HEAD（index 比較だとステージ済みの変更が差分から消え、サイドバーのバッジと食い違うため。実測で確認）。空出力を「変更なし」と決めず、追跡有無・git-dir の有無という事実で未追跡・コミット前・管理外を分ける。取得は @MainActor の GitDiffLoader が detached で行い、作業ツリー編集が .git/index を動かさない以上キャッシュは必ず陳腐化するためキャッシュしない。検証は実 git リポジトリを使う 14 件のテスト（swift test 1136 green）と、判定を壊すと未追跡テストだけが落ちることの確認。
<!-- SECTION:FINAL_SUMMARY:END -->
