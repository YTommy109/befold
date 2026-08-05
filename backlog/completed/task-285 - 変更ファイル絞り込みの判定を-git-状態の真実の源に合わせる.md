---
id: TASK-285
title: 変更ファイル絞り込みの判定を git 状態の真実の源に合わせる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 07:27'
updated_date: '2026-08-04 08:25'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 490000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)で確認された、TASK-264 の絞り込み判定に起因する不具合をまとめる。いずれも『行にキーがあるか』でメンバーシップを決めていることが根で、修正も同じ場所（FileListModel.visibleEntries / isGitChangeFilterEffective と、状態を配る SidebarNavigator）に集まる。

1. 未追跡ディレクトリの畳み込み: porcelain 既定(-unormal)は未追跡ディレクトリを 'dir/' 1 レコードに畳むため、新規フォルダー配下のファイルは gitStatuses にキーが無く、絞り込みで全部消える。1 階層上ではそのフォルダーに未追跡バッジが出ているため表示が自己矛盾する。TASK-263 の集約は祖先方向にしか広げていないので、ファイル側は祖先の畳み込みレコードに一致させる必要がある。
2. 綺麗なリポジトリでの誤縮退: isGitChangeFilterEffective は『非 git』と『変更が無い git リポジトリ』を区別できず、全部コミット済みのリポジトリではトグルが no-op になる。一方でメニューのチェックとヘッダーのアイコンは ON を示すため、機能が壊れて見える。判定はリポジトリを解決できたか（GitStatusResult.indexURL / ルートの有無）で行う。
3. 状態の遅延到着: performListing は一覧取得と refreshGitStatuses を別世代の非同期タスクで走らせるため、別リポジトリへ移動した直後は前のリポジトリの gitStatuses のまま新しい entries が適用され、一覧が一瞬 '..' だけになってから全件へ戻る。バッジだけなら誤描画で済んでいたが、絞り込みでは一覧そのものが消える。

前提となる事実: 2 と 3 は同じ『縮退の判定材料が statuses の中身になっている』ことが原因で、リポジトリ解決結果を持たせれば同時に解ける見込み。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 未追跡ディレクトリ配下のファイルが、絞り込み ON でも一覧に残る（1 階層上のバッジと表示が矛盾しない）
- [x] #2 変更が無い git リポジトリでトグル ON にしたとき、no-op ではなく意図した結果（変更ファイルが無いことが伝わる表示）になる
- [x] #3 別リポジトリ・非 git フォルダーへ移動した直後に、古い git 状態で一覧が空にならない
- [x] #4 縮退の判定がリポジトリを解決できたかどうかに基づき、statuses の中身に依存しない
- [x] #5 上記 3 ケースが単体テストまたは実 git リポジトリの統合テストで再現・検証される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
単純化の検討: 3 つの不具合はいずれも『FileListModel が git 状態を辞書 2 本の中身としてしか持たず、リポジトリを解決できたか・どのディレクトリの結果かを知らない』ことが根。個別に条件を足すのではなく、状態の持ち方を 1 つの値へ変える。

1. SidebarGitStatus（新規・純粋な値型）を作る: directoryKey（取得したディレクトリ）+ files + folders（GitFolderStatus.aggregate）。hasChange(at:) を純関数として持ち、ファイル自身の非 clean・フォルダー集約・『祖先が未追跡ディレクトリとして畳まれている』の 3 条件で判定する（畳み込み対応。folders の hasUntracked では同じフォルダー内の clean なファイルまで拾ってしまうため、files[ancestor].isUntracked を見る）。
2. GitStatusResult に repositoryRoot を持たせ、非 git と『git だが変更なし』を呼び出し側が区別できるようにする。
3. FileListModel の gitStatuses / gitFolderStatuses を gitStatus: SidebarGitStatus? の 1 本へ置き換える。nil = 非 git / 未到着 / 機能無効。絞り込みが効くのは showChangedFilesOnly かつ gitStatus があり、その directoryKey が currentDirectory と一致するときだけ（遅延到着・別リポジトリの古い状態はこの一致で自動的に外れる）。
4. 空状態の文言を絞り込み由来かどうかで分ける（TASK-287 の範囲だが、綺麗なリポジトリで『対応ファイルがありません』と出るのは本タスクの受け入れ条件 #2 を満たせないため同時に行う）。
5. テスト: hasChange の純関数テスト（畳み込み・祖先・clean 同居）、モデルの絞り込みテスト（綺麗なリポジトリ・ディレクトリ不一致）、実 git リポジトリの統合テスト（未追跡ディレクトリ配下が残る・非 git で空にならない）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: git 状態の持ち方を変えて 3 件をまとめて解消した。FileListModel の gitStatuses / gitFolderStatuses（辞書 2 本）を gitStatus: SidebarGitStatus? の 1 本に置き換え、nil = リポジトリ未解決、空の値 = 変更ゼロのリポジトリ、と意味を分けた。GitStatusResult に repositoryRoot を足し、Store は status 取得に失敗してもルートが解決できていればその事実を返す。

- 未追跡ディレクトリの畳み込み: SidebarGitStatus.hasChange が祖先チェーンを辿り files[ancestor].isUntracked を見る。folders[ancestor].hasUntracked では未追跡ファイルを 1 つ含むだけのフォルダーで同居する未変更ファイルまで拾うため使わない。
- 綺麗なリポジトリ: 縮退判定が nil かどうかになったため、変更ゼロでも絞り込みが効く。
- 遅延到着: SidebarGitStatus が取得元 directoryKey を持ち、表示中ディレクトリと一致するときだけ絞り込む。移動直後に古い状態で一覧が消えることがなくなった。追加の打ち消し処理は不要。
- 空状態の文言（TASK-287 と重複するため同時に実施）: 絞り込みで空になった場合は「変更されたファイルはありません」＋解除の案内に切り替えた。

検証: swift test 1067 passed（実 git リポジトリの統合テスト 2 件を新規追加: 未追跡フォルダー配下が残る / 綺麗なリポジトリで絞り込みが効く）。4 種類の変異（祖先判定の削除・ディレクトリ一致条件の削除・表示中エントリ例外の削除・空なら nil にする退行）を入れ、それぞれ狙ったテストが落ちることを確認済み。xcodebuild 成功、swiftformat 0 件、swiftlint は main 比で新規違反ゼロ（テストファイル分割により 1 件減）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git 状態の持ち方を SidebarGitStatus? へ一本化し、『リポジトリを解決できたか（nil か否か）』と『どのディレクトリの結果か（directoryKey）』を値そのものが持つようにして、未追跡ディレクトリの畳み込み・綺麗なリポジトリでの誤縮退・状態の遅延到着の 3 件を同時に解消した。実 git リポジトリの統合テストと 4 種類の変異確認（swift test 1067 passed）で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
