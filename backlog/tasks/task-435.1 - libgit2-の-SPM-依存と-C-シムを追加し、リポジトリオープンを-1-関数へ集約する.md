---
id: TASK-435.1
title: libgit2 の SPM 依存と C シムを追加し、リポジトリオープンを 1 関数へ集約する
status: In Progress
assignee:
  - '@Tommy109'
created_date: '2026-08-10 15:01'
updated_date: '2026-08-10 15:28'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-435
priority: high
type: task
ordinal: 666000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435（git 連携の libgit2 移行）の基盤サブタスク。個別の読み取り実装を移す前に、libgit2 を befold のビルドへ組み込み、全実装が共有する土台を用意する。

## 背景（親タスクの実測結果より）

- バインディングは SwiftGitX ではなく libgit2 の C API を直接使う。SwiftGitX には diff options / worktree 列挙 / submodule 列挙 / merge-base / ls-files 相当 / `git_libgit2_opts` がいずれも無い。
- 配布形態は ADR 0005 が想定した static XCFramework ではなく、`ibrahimcetin/libgit2`（libgit2 の C ソースを SPM の C ターゲットとしてビルドするパッケージ、`.library(name: "libgit2")` を公開）への依存とする。実測でフルビルド 6.4 秒・cmake 不要。
- `git_libgit2_opts` は C 可変長引数関数であり Swift から直接呼べない。固定引数へ落とす C シムターゲットが必要。
- リポジトリを開けない場合は `git_repository_open` が `-1` / klass=6(GIT_ERROR_REPOSITORY) / `unsupported extension name extensions.<名前>` で失敗する（partial clone / reftable / 未知の extensions すべて同じ形）。読み取り権限が無い場合は `-3`(GIT_ENOTFOUND)。いずれもクラッシュ・ハングはしない。

## スコープ

このサブタスクでは既存の git 呼び出しは 1 つも移さない。依存の追加と土台の設置、およびその土台のテストまで。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 libgit2 パッケージが Package.swift と project.yml の両方に追加され、`swift build` と `xcodebuild build -scheme befold` の両方が通る
- [ ] #2 git_libgit2_opts を固定引数で呼ぶ C シムターゲットが追加され、Swift から呼べることがテストで確認されている
- [ ] #3 起動時に GIT_OPT_SET_SEARCH_PATH で system/xdg/global の config 検索パスを無効化する処理が 1 箇所に置かれ、無効化後にユーザーの ~/.gitconfig が読まれないことがテストで担保されている（AC #7）
- [ ] #4 リポジトリを開いて後始末する処理が 1 関数に集約され、開けない場合に .unavailable 相当を返すことがテストで担保されている（AC #10）
- [ ] #5 開けないリポジトリのフィクスチャ（extensions.partialclone / 未知の extensions）を BefoldTestSupport に用意し、クラッシュせずモーダルも出さずに .unavailable 相当へ落ちることがテストで担保されている（AC #9）
- [ ] #6 libgit2 の初期化と終了（git_libgit2_init / git_libgit2_shutdown）の呼び出し回数と寿命が明示的に決められ、doc コメントに根拠が書かれている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
`/review-design` の結果（F1〜F5）を織り込んだ実装順。

1. **依存の追加**: `Package.swift` に `.package(url: "https://github.com/ibrahimcetin/libgit2.git", exact: "1.9.2")` を足し、`befold` ターゲットのみが `.product(name: "libgit2", package: "libgit2")` に依存する。QuickLook 拡張・CLI へは入れない（appex にコンパイルされない場所へ置くことで、git 依存が appex へ漏れる形を構造的に無くす）。`project.yml` の `packages:` にも同じ pin を書き、`befold` ターゲットの `dependencies` へ `- package: libgit2` を足す。`xcodegen generate` 後に `swift build` と `xcodebuild build -scheme befold` の両方を通す。
2. **C シムターゲット**: `git_libgit2_opts` は C 可変長引数で Swift から呼べないため、固定引数へ落とす C ターゲット（`BefoldApp/CGitShim/` 想定）を追加する。公開するのは検索パスの set/get 2 関数のみ。SwiftLintBuildToolPlugin は付けない（Swift を含まないため）。
3. **F2: 初期化と検索パス無効化を一度きりの static let に載せる**。`AppDelegate` から呼ぶ設計にしない。libgit2 は全 API 呼び出しの前に `git_libgit2_init` が必要で、テスト・将来の appex・CLI は `AppDelegate` を通らないため、配線漏れが静かに成立してしまう。`static let` の一度きり初期化（swift_once）に `git_libgit2_init` → SYSTEM/XDG/GLOBAL の検索パス無効化の順で載せ、**リポジトリを開く唯一の関数がそれに触る**。`git_libgit2_shutdown` は呼ばない（プロセス寿命と一致するため）。この判断は doc コメントに根拠を書く。
4. **F1 + AC #10: リポジトリを開く 1 関数**。`git_repository_open_ext` の失敗を 2 分岐だけで写像する。`GIT_ENOTFOUND` → 管理外（確定・キャッシュ可）、それ以外の失敗 → 使用不可（不明・キャッシュ不可）。**エラーメッセージ文字列（`unsupported extension name` 等）で判定しない**（libgit2 のバージョンで文言が変わる。実測では partial clone / reftable / 未知 extensions がすべて `-1` / klass=6 に収束するため、文字列を見る必要が無い）。メッセージは診断ログ用途に留める。`git_error_last()` は成功後も直前のエラーが残るため、rc < 0 のときだけ読む。
5. **F3: 集約を swiftlint の custom rule で守らせる**。`git_repository_open` / `git_repository_open_ext` の直接使用を、集約先ファイル以外で error にする（`feature_gate_direct_reference` と同じ形）。`import libgit2` 自体は禁止しない（435.2〜435.4 が他の API を使うため）。禁止するのは「開く」だけ。
6. **F4: AC #7 のテスト**。**検索パスを元へ戻す方向のテストは書かない**（libgit2 のオプションはプロセス全体に効き、Swift Testing の並列実行下で他テストの前提を壊す）。代わりに次の対で隔離を証明する。(a) bootstrap 後に SYSTEM/XDG/GLOBAL の検索パスが空であること、(b) 偽ホームに置いた gitconfig が `git_config_open_ondisk` では有効な設定として読めるのに、`git_config_open_default` からは見えないこと。加えて (c) リポジトリ内の config は引き続き読めること（無効化しすぎていないことの担保）。
7. **F5 + AC #9: 開けないリポジトリのフィクスチャとテスト**。`extensions.partialclone` と未知の `extensions.*` を設定したフィクスチャを **`befoldTests` 側に置く**（`project.yml` に `BefoldTestSupport` ターゲットが存在しないため、そこへ置くと Xcode 側のテスト経路に載らない。既存のずれ自体は別タスク）。テストは 4 の集約関数そのものを呼び、使用不可へ落ちること・クラッシュしないことを確認する。
8. **F5: open のコストを実測する**。`withRepository` は毎回 open/free する。`git_repository` はスレッド間共有できないため常駐化しない。open 単体のコストを計測し、キャッシュが不要ならその数値を Implementation Notes へ記録する（必要なら別タスクへ）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装結果（2026-08-11）

### 追加したもの

- `BefoldApp/CGitShim/`（`include/CGitShim.h` / `include/module.modulemap` / `CGitShim.c`）
  — `git_libgit2_opts` を固定引数へ落とす C シム。露出するのは検索パスの set/get 2 関数のみ
- `BefoldApp/befold/App/GitLibrary.swift` — 一度きりの初期化と `withRepository(at:_:)`
- `BefoldApp/befoldTests/GitLibraryTests.swift`（7 本）/ `GitLibraryIntegrationTests.swift`（2 本）
- `Package.swift` / `project.yml` に `ibrahimcetin/libgit2` を exact 1.9.2 で追加

### 実測

- `swift test`: **1401 tests / 205 suites を 20.397 秒で全通過**（exit 0）
- `xcodebuild build -scheme befold -destination 'platform=macOS'`: **BUILD SUCCEEDED**
- swiftlint: 全体 72 件（main のベースライン水準）。**新規ファイルの指摘は 0 件**
- swiftformat: `0/194` ほか全ターゲットで整形差分なし

### 計画 8（open のコスト実測）: キャッシュは不要

同じ libgit2 1.9.2 を使うプローブで、befold の worktree（1200 ファイル規模）に対して 200 回平均を計測した。

| 操作 | 1 回あたり |
|---|---|
| `git_repository_open_ext` + `git_repository_free` | **0.263 ms** |
| `/usr/bin/git --no-pager -C <root> rev-parse --show-toplevel` の spawn | **67.228 ms** |

**約 256 倍速い。** 呼び出しごとに開き直す設計で問題ない。`git_repository` を保持して使い回す
（スレッド間共有の制約を抱え込む）必要は無いことを数値で確定した。

### Xcode ビルドで詰まった点（次のサブタスクへの申し送り）

Xcode の SPM 統合は、**C ターゲットへ依存パッケージのヘッダ検索パスを自動では通さない**
（SwiftPM ビルドでは通る）。`CGitShim.h` の `#include <git2.h>` が
`'git2.h' file not found` で落ちた。`project.yml` の `CGitShim` ターゲットへ

    HEADER_SEARCH_PATHS: "$(BUILD_DIR)/../../SourcePackages/checkouts/libgit2/include"

を足して解決した。この相対関係は `-derivedDataPath` を変えても崩れない
（release.yml は `-derivedDataPath build` を使う）。

### 未完了

`.swiftlint.yml` への custom rule `git_repository_open_outside_git_library` の追加（計画 5 / F3）は、
PreToolUse フックが `.swiftlint.yml` の編集をユーザーの明示指示なしにブロックするため保留。
ユーザーの許可待ち。ルールが入るまで「開くのは GitLibrary だけ」は doc コメントだけで守られている状態。
<!-- SECTION:NOTES:END -->
