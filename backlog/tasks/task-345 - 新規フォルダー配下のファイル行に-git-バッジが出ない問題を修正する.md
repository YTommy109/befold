---
id: TASK-345
title: 新規フォルダー配下のファイル行に git バッジが出ない問題を修正する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-06 07:56'
updated_date: '2026-08-06 08:24'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 611000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーで、新しく作った未追跡フォルダーの配下にあるファイルの行に git ステータスバッジが一切出ない（'?' も出ない）。同じ行が「変更ファイルのみ表示」フィルターには残るため、フィルター結果とバッジ表示が食い違う。

原因（コード参照）:
- porcelain の既定 `-unormal` は未追跡ディレクトリを `dir/` の 1 レコードへ畳むため、新規フォルダー配下のファイルは statuses にキーを持たない（BefoldApp/befold/App/SidebarGitStatus.swift:44-52 に既知として記述あり）。
- TASK-285 でこの畳み込みへの対処が hasChange 側にだけ入った。hasChange（SidebarGitStatus.swift:53-57）は hasUntrackedAncestor で祖先を辿るが、バッジの供給元である fileStatus(at:)（同 :34-37）は files の直接引きのままで祖先を辿らない。
- 結果、Viewer/FileListView.swift:163-164 → Viewer/FileListEntryRow.swift:71-73 の経路でバッジが nil になる。

単純化の検討結果: 新しい状態や分岐を足さず、fileStatus(at:) 側で既存の hasUntrackedAncestor を使い、畳み込み配下では isUntracked の GitFileStatus を返すようにするのが最小。そうすると hasChange は `fileStatus(at:) != nil || folders[pathKey] != nil` に縮み、現在 2 か所に分かれている祖先判定の経路が 1 本になる（判定のずれが再発しない構造になる）。

FeatureGate.isSidebarGitStatusEnabled 配下のため、コミットには (gate) スコープを付けること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 未追跡フォルダー配下のファイル行に、未追跡を示す灰色の '?' バッジが表示される
- [x] #2 fileStatus(at:) と hasChange(at:) の判定が一致し、フィルターに出る行には必ずバッジが付く（祖先判定のロジックが 1 か所に集約されている）
- [x] #3 追跡済みフォルダー内の未変更ファイルにバッジが付かないこと（TASK-285 のコメントが警告している誤判定）を検証するテストがある
- [x] #4 修正を戻すと落ちることを確認したテストが追加されている
- [x] #5 swiftlint の main 比ベースライン差分がゼロである
- [x] #6 未追跡フォルダー配下の「サブフォルダー」行にも集約バッジが表示される（ファイル行だけでなく兄弟の経路も直っている）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarGitStatus.fileStatus(at:) を、files に無い場合に hasUntrackedAncestor(of:) を見て未追跡の GitFileStatus を返すよう変える。
2. hasChange(at:) を fileStatus(at:) != nil || folders[pathKey] != nil に縮め、祖先辿りの経路を fileStatus 側 1 本に集約する。
3. doc コメントを新しい責務分担に合わせて書き直す（畳み込みの説明を fileStatus 側へ移す）。
4. テスト: 未追跡フォルダー配下のファイルが '?' バッジを得ること、追跡済みフォルダー内の未変更ファイルにバッジが付かないこと（TASK-285 が警告する誤判定）を追加し、修正を戻すと落ちることを確認する。

--- /review-design の結果（実装前）---
5. [項目3 兄弟箇所] **同型の穴がフォルダー行にもある。** 畳み込まれた未追跡ディレクトリ配下の「サブフォルダー」行も folders にキーを持たないためバッジが出ない（GitFolderStatus.aggregate は畳み込まれたディレクトリ自身のキーしか作らない = GitFolderStatus.swift:19-23）。ファイル行だけ直すと TASK-320 と同じ「予告した穴を 1 箇所だけ直す」形になる。folderStatus(at:) にも同じ祖先辿りのフォールバック（hasUntracked: true の GitFolderStatus を返す）を入れ、両方を同時に直す。
6. [項目9 担保] 「フィルターに出る行には必ずバッジが付く」を prose ではなくテストで縛る。フィクスチャ上の全パスキーについて hasChange(at:) == (fileStatus(at:) != nil || folderStatus(at:) != nil) を検証するテストを置く。これで 2 つの経路が再び食い違ったら落ちる。
7. [項目6 コスト] 変更後は「変更が無い行」のバッジ描画でも祖先をルートまで辿る（従来 fileStatus は辞書 1 回引きだった）。deletingLastPathComponent は純粋な文字列処理で syscall を含まず、深さも一覧のパス階層ぶんに限られるためキャッシュは足さない（状態を増やさない方針を優先）。
8. [項目1/2] 合成して返す状態の真実の源は files[ancestor].isUntracked（畳み込みの事実そのもの）であり、folders[ancestor]?.hasUntracked ではない。SidebarGitStatus.swift:50-52 が警告する誤判定（未追跡ファイルを 1 つ含むだけの追跡済みフォルダー内の未変更ファイル）を招かないこと。既存の hasUntrackedAncestor をそのまま使う。
9. [項目4 表示] 新しい l10n は不要。返すのは既存の untracked 状態で、'sidebar.gitStatus.untracked' がそのまま使われる。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-06 実装完了。

変更点（すべて App/SidebarGitStatus.swift）:
- fileStatus(at:) が files に無いとき hasUntrackedAncestor(of:) を見て isUntracked の GitFileStatus を組み立てて返す
- folderStatus(at:) にも同じフォールバックを入れた（設計レビューで見つけた兄弟の穴。畳み込み配下のサブフォルダーも folders にキーを持たない）
- hasChange(at:) が独自判定を持たず fileStatus/folderStatus の引き当てに委ねる形になり、祖先辿りの経路が hasUntrackedAncestor 1 本に集約された
- doc コメントを新しい責務分担へ書き直した（畳み込みの説明を hasUntrackedAncestor へ移動）

新規テスト befoldTests/SidebarGitStatusTests.swift（xcodegen generate 実行済み）:
- 畳み込み配下のファイル / サブフォルダーが引けること
- TASK-285 が警告する誤判定（未追跡ファイルを 1 つ含むだけのフォルダーの兄弟）が起きないこと
- hasChange == (fileStatus != nil || folderStatus != nil) をフィクスチャ内の全パスキーで検証（2 経路が再び食い違ったら落ちる担保）

検証（実測）:
- 実装前に新規テストを流して 6 件失敗を確認（fileStatus/folderStatus が nil、hasChange との不一致 3 件）。実装後は swift test で 1178 tests / 175 suites すべて成功（実装前の総数 1173 + 新規 5）
- swiftlint: SidebarGitStatus.swift・SidebarGitStatusTests.swift とも警告 0 件。origin/main 側の SidebarGitStatus.swift も 0 件でベースライン差分ゼロ
- swiftformat: 0/167 files formatted（整形の必要なし）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
未追跡ディレクトリの porcelain 畳み込み(-unormal)への対処が hasChange 側にしか入っておらず、新規フォルダー配下の行にバッジが出なかった問題を修正した。祖先辿りを fileStatus(at:) へ移し、hasChange はバッジの引き当てそのものに委ねる形へ縮めて経路を 1 本に集約。設計レビューで見つかった同型の穴（配下のサブフォルダー行）も folderStatus(at:) 側で同時に塞いだ。実装前に新規テスト 6 件が落ちることを確認し、実装後 swift test 1178 件成功、swiftlint は main 比で差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
