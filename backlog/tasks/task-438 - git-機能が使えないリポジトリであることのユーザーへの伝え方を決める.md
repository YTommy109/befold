---
id: TASK-438
title: git 機能が使えないリポジトリであることのユーザーへの伝え方を決める
status: To Do
assignee: []
created_date: '2026-08-10 15:08'
updated_date: '2026-08-13 13:57'
labels:
  - ux
dependencies:
  - TASK-435.1
priority: medium
type: task
ordinal: 110000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-435（libgit2 移行）の設計レビュー（`/review-design` TASK-435.1）で切り出した未決事項。

ADR 0005 の Fallback 節は「libgit2 がリポジトリを開けない場合、befold は git 機能だけを静かに落とし、通常のビューアとして動作を継続する。エラーダイアログは出さない」と決めている一方で、次を未決のまま残している。

> なお、この方針は「git 機能が使えないことをユーザーに一切伝えない」という意味ではない。
> 何も伝えないと ADR 0003 の Context にある「原因不明の無反応」と同じ形になるため、
> 伝え方（サイドバーの控えめな注記など）は実装時に決める。ただしモーダルでの中断は取らない。

TASK-435.1 では既存の `.unavailable` 経路へ合流させるだけで新しい表示は増えないため、この決定は宙に浮く。落とさないよう独立したタスクとして起票する。

## 対象となる状況

- partial clone のリポジトリ（libgit2 が開けない。実 git は開ける）
- reftable 形式のリポジトリ（同上。libgit2 の reftable 対応は 2026-08 に main へマージされたがリリース未収録）
- 未知の `extensions.*` を持つリポジトリ
- `.git` を読む権限が無い場合

## 縮退の内容（ADR より）

- サイドバーの git ステータスバッジを表示しない
- 差分表示モードを選択不可にする（既存の「管理外」扱いと同じ）
- Quick Open の候補列挙をディレクトリ走査へ切り替える

## 論点

1. 「git 管理外のフォルダ」と「git リポジトリだが befold が扱えない」を表示上で区別するか。区別しないなら、その判断の根拠を記録する
2. 区別するなら、どこに何を出すか（サイドバーの注記 / ステータス行 / 何もしない）
3. ADR 0003 の「原因不明の無反応」と同じ形になっていないことを、どうテストで担保するか
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 libgit2 が開けないリポジトリを開いたとき、BaseDirectoryIndicator が「Plain folder」と表示せず、git リポジトリだが befold では扱えないことが伝わる表示になっている
- [ ] #2 「git 管理外」と「扱えないリポジトリ」を区別する判断とその根拠、および区別しない/できない事項（失敗理由の種別・.git 読み取り権限なし）が Implementation Notes に記録されている
- [ ] #3 git が使えないとき差分表示モードが選択不可になっている（ADR の記述どおり。ViewerCapabilities.canSelectDiffMode が git の可用性を見る）
- [ ] #4 ADR の Fallback 節が「実装時に決める」から確定した記述へ更新され、ADR 0003 への誤った参照（「原因不明の無反応」は ADR 0003 に存在しない）が正されている
- [ ] #5 決めた挙動が破れたら落ちるテストが用意されている（扱えないリポジトリで「Plain folder」と表示しないこと・差分モードが選べないこと）
- [ ] #6 ADR 番号の衝突が解消され（libgit2 側を 0006 へ振り直す）、参照箇所が追随している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決定（2026-08-13、ユーザー確認済み）

**論点 1: 区別する。ただし BaseDirectoryIndicator の 1 箇所のみ。**

根拠は「伝えていない」ことより「誤って伝えている」ことのほうが問題だから。BaseDirectoryIndicator.swift:12,26-27 はアイコンとツールチップを kind == .gitRoot の二値で決めており、kind は SidebarBaseDirectoryResolver.swift:48 の repositoryRoot(forDirectoryAt:) -> URL? 由来。扱えないリポジトリはここが nil になるため、git リポジトリなのに folder アイコン + 「Plain folder」と表示される。これは静かな縮退ではなく事実と異なる表示。

しかも BaseDirectoryIndicator は FeatureGate 配下ではないため stable のユーザーに見える。一方、ADR の縮退 3 点のうちサイドバーのバッジは FeatureGate.isSidebarGitStatusEnabled、差分は isSourceDiffEnabled の配下で dev 限定（FeatureGate.swift:65-67, 77-79）。つまり stable での実害はこの 1 箇所に集中している。

バナー・注記行は足さない。モーダルも取らない（ADR の方針を維持）。

**区別しない/できない事項（AC #2 の記録）**

- **失敗理由の種別は出さない**: GitLibrary.OpenFailure（GitLibrary.swift:30-38）は partial clone / reftable / 未知の extensions.* をすべて .unusable の 1 値へ畳んでいる。libgit2 のエラーメッセージは版で変わりうるため見ない、という意図的な設計判断（GitLibrary.swift:116-117）。理由別の文言を出すと、型が持っていない情報を騙ることになる。
- **.git の読み取り権限なしは区別できない**: git_repository_open が GIT_ENOTFOUND を返すため .notARepository へ落ちる（ADR の 2026-08-11 実測追記に記録済み）。「git 管理外」と完全に同じ扱いになり、分ける手段がない。起票時の「対象となる状況」4 点のうち 1 点はこの理由で対象外。

**論点 3 の前提が存在しなかった（記録）**

起票時の論点 3 は「ADR 0003 の Context にある『原因不明の無反応』と同じ形になっていないことをどうテストで担保するか」だったが、docs/adr/0003-git-status-guard-in-file-list-model.md にこの語句は存在しない（grep -rn '原因不明' docs/ backlog/ の一致は ADR 0005:207 とその引用のみ）。ADR 0003 の Context が述べているのは反映可否の判定が 3 状態に分散して順序回帰が 5 回続いたという内部設計の話で、ユーザーへの伝え方は扱っていない。ADR 側の誤った参照として AC #4 で訂正する。

**論点 2 の追加発見: ADR と実装の乖離**

ADR の縮退 3 点のうち「差分表示モードを選択不可にする」は未実装。ViewerCapabilities.swift:70 の canSelectDiffMode は git の可用性を見ておらずファイル種別のみで決まる。モードは選べて、ViewerDiffPresenter.displayableDiff(_:)（:117-120）が nil を畳んで黙ってソース表示へ戻る。ユーザー確認の結果、**ADR どおりに実装する**方針とした（ADR の記述は変えない）。

**ADR 番号衝突**

0005 が 2 本ある（0005-bundle-viewer-js-with-esbuild.md = backlog decision-5、0005-git-integration-via-libgit2.md = decision-6）。decision 番号に合わせ、**libgit2 側を ADR 0006 へ振り直す**。参照箇所も追随させる。
<!-- SECTION:NOTES:END -->
