---
id: TASK-122
title: ドキュメント内のファイルパス参照を表示時に解決してリンク化する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-07-24 12:53'
updated_date: '2026-07-25 10:21'
labels: []
dependencies: []
documentation:
  - docs/superpowers/plans/2026-07-24-clickable-path-resolution.md
priority: low
ordinal: 200000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ドキュメント（Markdown リンク・本文/コード中のパス文字列）に書かれたファイルパスを、表示時に実ファイルへ解決し、解決できたものだけをクリック可能なリンクとして表示する。現状はパスの見た目を無条件にクリック可能化し、クリックした瞬間に相対パス解決＋存在確認するため、モノレポや暗黙のドキュメントルート起点で書かれたパスが解決できず「リンクに見えるのに開けない」状態になっている。解決を表示時に前倒しし、実在しないパスはリンクにしないことで信頼できるリンク表示にする。将来のコンテキストメニュー「パスをコピー」機能の布石にもなる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ドキュメントに書かれたファイルパスのうち、実ファイルに解決できたものだけがクリック可能なリンクとして表示される
- [ ] #2 解決できないパスは通常テキストで表示され、クリック可能に見えない（偽リンクを出さない）
- [ ] #3 リンクをクリックすると対象ファイルが befold で開く（無修飾=同一ウィンドウ、Cmd=新規ウィンドウ）。プロトコル付き(http(s) 等)はリンク維持、#アンカーはページ内スクロール
- [x] #4 開いているファイル基準の相対パス・絶対パスで実在するものは git 管理外でも解決・リンク化される
- [x] #5 git リポジトリ配下では、相対で解決できないパスも git 追跡ファイル(git ls-files)への構成要素単位サフィックス一致で解決し、候補が複数ある場合は開いているファイルに最も近いものを決定論的に選ぶ
- [x] #6 外部での git ブランチ/ワークツリー切替・commit 後、リンク解決が最新の追跡ファイル集合に追従する
- [x] #7 git 管理外では、相対/絶対で実在確認できないパスにはリンクを貼らない
- [x] #8 表示時解決とクリック時オープンが同一の解決ロジックを使う（結果が一致する）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装完了（ブランチ feat/document_path、9 コミット）

計画書 docs/superpowers/plans/2026-07-24-clickable-path-resolution.md の 7 タスクを subagent-driven development で実施。各タスクごとに仕様適合＋品質のレビューを行い、Task 4/6/7 は修正ラウンドを 1 回ずつ経て全指摘解消。最後にブランチ全体レビューと修正ウェーブ 1 回。

### 構成
- BefoldKit（Foundation のみ依存）: SuffixPathMatcher（構成要素単位サフィックス一致＋近さランキング）、TrackedPathResolver（相対/絶対で実在 → git 追跡ファイルへのサフィックス一致の順で解決する単一情報源）、GitFileIndexing / ResolvedReference、ReferenceResolver.localPathString
- befold（app、Process を持つ副作用層）: GitCommandRunner（git 実行の一元化）、GitRepository（ルート検出・追跡ファイル列挙・.git/index fingerprint）、GitCommandFileIndex（fingerprint によるキャッシュ無効化。ViewerWindowManager が単一インスタンスを保持し全ウィンドウで共有）
- ブリッジ: JS が描画後に候補パスを収集 → resolveReferences メッセージ → Swift が解決 → _mmdApplyResolvedReferences で解決済みだけをリンク化。解決が返るまでは中立表示（偽リンクを出さない）
- クリック時の handleOpenReference も同じ TrackedPathResolver を使う（解決の単一情報源）

### 計画からの逸脱（レビューでいずれも妥当と判定）
- JS は単一 pending リストではなく要求ごとの FIFO バッチキュー。計画どおりだと再描画中に応答が追い越されたとき、問い合わせていないパスまで dead 化して実在リンクが恒久的に死ぬ
- appendChunk の解決呼び出しは _annotatePathRefs() 直後ではなく関数末尾。CSV 行・行番号テーブル行は _walkTextNodes を直呼びするため計画位置では漏れる
- pathResolver は store.fileReader を共有（ViewerStore.fileReader を private→internal）。表示時とクリック時で存在判定のオラクルを 1 つに保つため

### 最終レビューで発見・修正したセキュリティ問題
git ls-files / rev-parse が、開いた文書のあるツリーの .git/config にある core.fsmonitor を実行していた（任意コマンド実行）。warm() により文書を開いた瞬間にバックグラウンドで発火するためクリック不要。.git/ を同梱した書庫を展開して中の .md を開くだけで成立し、safe.directory も効かない。GitCommandRunner に -c core.fsmonitor= / -c core.hooksPath=/dev/null / GIT_OPTIONAL_LOCKS=0 を入れて封鎖し、付与を固定するテストを追加。git 2.54.0 で再現とミューテーション検証済み。

### 検証
- swift test（--skip なし）680 tests 全通過
- npx jest 295 tests 全通過（JS 状態機械の失敗モード: 再描画中の古い応答、チャンク追加時の再収集、pending 中のクリック遮断、ホストハンドラ不在時の非フリーズ、空キュー no-op）
- swift scripts/webview-smoke.swift PASS（CSP 下のスクリプト稼働・mmd/md 描画・外部画像と data: iframe のブロック）

### 未検証
AC #2 / #3 の見た目・対話部分（リンク色/下線と素のテキストの描き分け、Cmd クリックでの新規ウィンドウ、#アンカーのページ内スクロール）は実アプリでの目視確認が必要。webview-smoke は CSP/描画の回帰確認であってこの確認ではない。

### 後続タスク
TASK-144（resolveReferences の async 化）に、キャッシュ cold 時のメインスレッド git 実行、ウィンドウ間共有ロックの別リポジトリ間での待ち増加、アプリ寿命キャッシュの eviction 不在、GitCommandRunner のタイムアウト不在を集約済み。
<!-- SECTION:NOTES:END -->
