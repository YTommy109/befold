---
id: TASK-403
title: ネストしたリポジトリ・サブモジュール配下の git ステータスの扱いを決める
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 02:43'
updated_date: '2026-08-10 04:46'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 660000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーの git ステータスは、親リポジトリの `git status --porcelain=v2` 1 回ぶんをリポジトリルート配下の全階層へ適用する（TASK-361.2）。ネストしたリポジトリとサブモジュールは、この 1 回では正しく答えられない。

## 実測（2026-08-10、一時ディレクトリで再現）

ネストした独立リポジトリでは `child/` が「未追跡ディレクトリ」1 レコードへ畳まれる。サブモジュールは `1 .M S.MU 160000 ... sub` の 1 レコードのみで、配下ファイルは一切出ない。

## コード上の帰結

- **ネストしたリポジトリ**: `child/` が `isUntracked` で入るため `SidebarGitStatus.hasUntrackedAncestor` が効き、配下の全行が未追跡としてバッジ付き・絞り込みで残る。子リポジトリ側でコミット済み・クリーンなファイルまで「新規」と表示される
- **サブモジュール**: `sub` は `isUntracked = false`（GitStatusReader.parseChangedEntry）。配下ファイルはキーを持たず未追跡祖先も無いため `hasChange` が false になり、**「変更されたファイルのみ表示」で配下が全部消える**

## いつ表面化するか

ドリルダウンでは、子リポジトリへ降りた時点で `git rev-parse --show-toplevel` が子ルートを返して取り直すため表面化しない。表面化するのは次の 2 経路。

1. **選択中のサブフォルダーのプレビュー**（FolderListingView）— TASK-361.2 で絞り込みがリポジトリ配下の全階層に効くようになったため、サブモジュールのフォルダーを選ぶと配下が空になる。**現時点で到達可能**
2. **ツリー展開**（TASK-361.4）— 親を表示したまま子リポジトリ／サブモジュール配下の行が並ぶ

## 選択肢

1. 現状のまま出し、doc に限界を書く（TASK-361.2 で暫定的にこれを実施済み）
2. `git status` のオプションでサブモジュールを展開する（別プロセスコスト増）
3. ネスト／サブモジュール境界を検出し、その配下は「判定不能」として絞り込みから除外する（＝消さずに残す）

「変更していないファイルが黙って消える」（サブモジュール）は「余計なバッジが出る」（ネスト）より害が大きいため、少なくともサブモジュール側は 3 の縮退を検討する。

## 現状

TASK-361.2 では選択肢 1（限界を `SidebarGitStatus.repositoryRootKey` の doc に明記）に留めた。FeatureGate 配下の機能のため外部利用者には未露出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サブモジュール配下の行が「変更のみ表示」で黙って消えない
- [x] #2 ネストしたリポジトリ配下の行が、親リポジトリの畳み込みによって誤って「新規」と表示されない
- [x] #3 選んだ方針（1/2/3 のいずれか）と理由が Implementation Notes に記録されている
- [x] #4 判定がユニットテストで担保されている（実 git を起こさず、SidebarGitStatus への入力で再現できる形）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
方針: 選択肢 3（境界を検出し配下を「判定不能」として縮退）。/review-design 反映後の版。

## 境界の検出（GitStatusReader、メインアクター外）
1. 3 系統の和を Set<String>（正規化パスキー）として求める。実測でどれか 1 つでは足りない:
   - (a) .gitmodules の登録パス: git config -z --file <root>/.gitmodules --get-regexp '^submodule\..*\.path$'（clean なサブモジュールは status に 1 行も出ないためこれが必須）
   - (b) porcelain v2 の <sub> フィールドが 'S' 始まりのレコード（未登録サブモジュール用）
   - (c) 畳まれた未追跡ディレクトリ（'? dir/'）配下の <dir>/.git を FileReading で stat（ネストしたリポジトリ用）
2. parsePorcelainV2 の戻り値をエントリ配列からエントリ + サブモジュールパスを持つ構造体へ変える（純関数のままテスト可能に保つ）。
3. GitStatusReader へ fileReader: FileReading を注入する。

## 配管
4. GitStatusSnapshot / GitStatusResult / SidebarGitStatus へ indeterminateRoots: Set<String> を通す。
5. GitStatusResult の構築点が GitStatusStore:82 と :102 の 2 箇所あるため、GitStatusResult(snapshot:root:) の init 1 本へ畳む（片方だけ埋める TASK-320 型の取り残しを構造的に防ぐ）。

## 判定
6. SidebarGitStatus の祖先走査を 1 本にまとめ、各ステップで「境界か」→「未追跡の畳み込みか」の順に見る。ネストしたリポジトリのディレクトリは両方に該当するため、境界が勝たないと AC#2 が残る。境界配下は fileStatus / folderStatus とも nil。境界の行そのものは従来どおり自分の状態を返す。
7. FileListFilter.apply に presentedPathKey と同じ層の例外を足す（hasChange 自体には条件を足さない = TASK-345 の不変条件を保つ）。

## 担保（破れたら落ちるもの）
8. 境界配下は「バッジが出ない」かつ「絞り込みで消えない」を 1 テストで固定する（片方だけの実装では落ちる）。
9. 境界の行そのものが自分の状態を保つテスト（サブモジュール行の変更バッジ / ネスト行の未追跡バッジ）。
10. ツリー展開で祖先が足し戻されることを SidebarTreeFilter 経由で確認する。
11. パース側: S フィールド検出、.gitmodules 出力（-z, NUL 区切り）のパース、畳まれた未追跡ディレクトリの .git stat をフェイクで固定。

## 受け入れる限界（doc に明記）
12. .gitignore されたネストしたリポジトリは status に 1 行も出ないため検出できない（実測）。ignore された内容が「変更のみ表示」に出ないのは全ファイル共通の挙動であり一貫している。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 選んだ方針と理由（AC#3）

選択肢 3（境界を検出し、その配下を「判定不能」として絞り込みから除外＝消さずに残す）を採用した。

選択肢 2（git のオプションでサブモジュールを展開する）を採らなかったのは、実測で**追加のプロセス起動なしに境界を検出できる**と分かったため。展開すると子リポジトリぶんの status を毎回起こすことになり、コストが階層数に比例する。

## 実測（2026-08-10、一時リポジトリ）

- clean なサブモジュール: `git status --porcelain=v2` に**1 行も出ない**
- 汚れたサブモジュール: `1 .M S.MU 160000 ... sub` の 1 行のみ（`<sub>` フィールドが S 始まり）
- ネストしたリポジトリ: `? child/` の 1 行へ畳まれる
- .gitignore されたネストしたリポジトリ: **1 行も出ない**
- `git config -z --file .gitmodules --get-regexp '^submodule\..*\.path$'` → `submodule.sub.path\nsub\0`、.gitmodules が無ければ rc=1

## 境界の検出は 3 系統の和（どれか 1 つでは足りない）

1. .gitmodules の登録パス（clean なサブモジュールはここでしか拾えない）
2. status レコードの `<sub>` が S 始まり（未登録サブモジュール用）
3. 畳まれた未追跡ディレクトリのうち .git を持つもの（ネストしたリポジトリ用）

2 は `parseRecord` の結果とは独立に読む。XY が clean で表示対象にならないレコードでも境界は境界であり、表示対象かどうかで検出を左右させると「バッジの出ないサブモジュールの配下だけが黙って消える」が残る。

## 設計上の要点

- **祖先の走査を 1 本にまとめ、各ステップで境界を未追跡の畳み込みより先に見る**（`SidebarGitStatus.ancestorFact(of:)`）。ネストしたリポジトリのディレクトリは「未追跡の畳み込み」と「境界」の両方に該当するため、別々に走査すると AC#2 が満たせない
- 絞り込みの例外は `FileListFilter` 側（presentedPathKey と同じ層）に置き、`hasChange` には条件を足していない（バッジと絞り込みを食い違わせないための TASK-345 の不変条件を保つため）
- `GitStatusResult` の構築が 2 箇所（新規取得・キャッシュ再利用）にあったため `init(snapshot:repositoryRoot:)` 1 本へ畳んだ。実際に今回フィールドを足した時点で両方がコンパイルエラーになり、片方だけ埋める取り残し（TASK-320 と同型）が構造的に起きない形になっている

## 受け入れた限界

.gitignore されたネストしたリポジトリは status に 1 行も出ないため検出できない（実測）。ignore された内容が「変更のみ表示」に出ないのは全ファイル共通の挙動であり一貫しているため、縮退の対象外とした。`GitStatusReader.indeterminateRoots(at:parsed:)` の doc に明記済み。

## 検証

- `swift test`: 1333 tests / 195 suites 全て pass
- 実 git を起こす通し確認 1 本を追加（`detectsSubmoduleAndNestedRepositoryBoundaries`）。clean なサブモジュールが status に 1 行も出ないこと自体をアサートし、検出の出所が .gitmodules 側であることを固定している
- swiftlint: main とのベースライン差分で**新規違反ゼロ**（既存違反は AppDelegate 等の行数変動のみで、いずれも本変更とは無関係）
- swiftformat: 差分なし
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ネストしたリポジトリ・サブモジュールの境界を検出し、その配下を「変更なし」ではなく「判定不能」として扱うようにした（選択肢 3）。境界配下はバッジを出さず、かつ「変更のみ表示」でも行を残す。

検出は追加のプロセス起動なしで済む 3 系統の和（.gitmodules の登録・status の <sub> フィールドが S 始まり・畳まれた未追跡ディレクトリの .git 存在）。祖先の走査を 1 本にまとめ、境界を未追跡の畳み込みより先に判定することで、ネストしたリポジトリ配下の誤った「新規」表示を解消した。

検証: swift test 1333 件全て pass。実 git で clean なサブモジュールとネストしたリポジトリの検出を通しで確認。swiftlint は main とのベースライン差分で新規違反ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
