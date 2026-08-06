---
id: TASK-330
title: 差分の更新契機がウィンドウ間・index 変更に届いていない問題を修正する
status: Done
assignee: []
created_date: '2026-08-06 01:47'
updated_date: '2026-08-06 02:31'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 502000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
refreshDiff の呼び出し元は toggleSourceDiff（自ウィンドウのみ）と store.onContentReloaded の 2 箇所だけ。DiffDisplayPreference はアプリ全体で共有されているのに、⌘D で ON にしても他ウィンドウは差分を取得しないため、メニューのチェックだけ付いて画面は変わらない（他ウィンドウで ⌘D を押すと共有フラグが OFF に反転し、元のウィンドウの差分が消える）。また GitIndexWatch による .git/index 変更・windowDidBecomeKey はバッジのみ更新し refreshDiff を呼ばないため、git commit -a / checkout / stash 後もコミット済みの差分が残り続ける。ViewerWindowController.swift:876 のコメントは「バッジと差分がずれないよう契機を 1 つにする」と主張しているが、バッジは 3 契機・差分は 1 契機になっている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 2 つのウィンドウを開いた状態で片方の ⌘D が両方に反映される
- [x] #2 git commit -a 後に表示中の差分が更新（消滅）する
- [x] #3 バッジと差分の更新契機が実際に同一であることを担保するテスト、または構造上ずらせない配線がある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー(/review-design)の結論

### 方針
1. **ウィンドウ間伝搬**: toggleHiddenFiles / toggleChangedFilesOnly と同型にする。
   ViewerWindowController.toggleSourceDiff は delegate へ通知するだけにし、
   ViewerWindowManager.toggleSourceDiff() が diffDisplayPreference.isEnabled を反転して
   allControllers 全員の refreshDiff() を呼ぶ(先例: ViewerWindowManager.swift:114-124, 471)。
2. **契機の一本化**: SidebarNavigator.applyGitStatus が accepted のときに
   SidebarNavigatorHost の必須メソッド(gitStatusDidApply())を呼び、
   ViewerWindowController がそこで refreshDiff() する。onContentReloaded からの
   直接呼び出しは削除。プロトコル必須メソッドなので外すとコンパイルが通らない(AC#3)。

### レビューで確定した追加修正(実装前に方針へ織り込む)
- **項目6(高頻度経路のコスト)**: refreshDiff は diffLoader / isEnabled しか見ておらず
  (ViewerWindowController+Diff.swift:24-30)、PDF・画像でも git diff を起こす。表示側は
  ViewerContentView.swift:35 で捨てている。契機が 2 から「バッジと同数(=.git/index 書き込みごと)」へ
  増えるため、refreshDiff の先頭に capabilities.canToggleDiff のガードを足す
  (ViewerCapabilities.swift:59 = isPresentingDocument && showsCodeContent)。TASK-324 と同型。
- **項目8(非同期の世代管理)**: refreshDiff の着地判定は fileURL の一致だけで、
  isEnabled を見ていない。取得中に OFF にすると store.diffText へ古い本文が入る
  (表示は ViewerContentView 側のゲートで隠れるが状態が汚れる)。着地時に
  diffDisplayPreference.isEnabled を再確認する。全ウィンドウ同時発行で重なりが増えるため先に直す。

### 検討して「該当しない/問題なし」と判断したもの
- 項目1(真実の源): 新設の述語は無い。契機の配線だけを変える。
- 項目2(不変条件): diffText の生成元は refreshDiff の 1 箇所のままで、
  クリア側(ViewerStore.openFile / ViewerStore.swift:217)にも触らない。
- 項目3(消費経路): diffText の消費は ViewerContentView.swift:35 の 1 箇所。
  共有 preference は @Observable なので、manager 側で反転すれば他ウィンドウの
  body も再評価される。メニューのチェック(ViewerWindowController.swift:802-808)も
  共有 preference を読むため追従する。
- 項目4(新しい表示状態): 新しい状態は増えない。
- 項目5(順序): SidebarNavigator は init 内で attach 前に取得を起こしうるが、host は weak で
  nil のため初回は落ちる。初回の差分は最初の onContentReloaded → refreshGitStatuses →
  applyGitStatus(attach 済み)で取れる。
- 項目7(測るものと守るもの): AC#3 は「契機が同一」を守りたいので、テストは
  refreshDiff を直接呼ぶのではなく navigator の git 状態反映経路から観測する。
- **stale で捨てられた場合の取り残し**: FileListModel.applyGitStatus は
  sequence が新しければ常に true を返す(FileListModel.swift:189-199)。false になるのは
  「より新しい結果が既に反映済み」のときだけで、その結果自身が callback を撃っている。
  よって取り残しは起きない。
- **対象の粒度差(差分=表示中ファイル / バッジ=表示中ディレクトリ)**: 束ねてよい。
  別ディレクトリを見ていても表示中ファイルの差分は取り直すべきで、無駄打ちの上限は
  項目6 のガードで抑える。

## 作業手順
1. refreshDiff にガード 2 つ(canToggleDiff / 着地時 isEnabled)を足す
2. SidebarNavigatorHost に必須メソッドを追加、applyGitStatus の accepted 時に呼ぶ
3. ViewerWindowController 側で refreshDiff を配線、onContentReloaded から削除
4. toggleSourceDiff を delegate 経由へ、ViewerWindowManager.toggleSourceDiff を追加
5. テスト: (a) 2 ウィンドウで片方のトグルが両方へ届く (b) git 状態反映経路から差分が取り直される
6. swiftformat / swiftlint ベースライン差分ゼロ / swift test
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装と検証。

## 変更
- ViewerWindowController.toggleSourceDiff は delegate へ通知するだけにし、反転と全ウィンドウの refreshDiff は ViewerWindowManager.toggleSourceDiff() が行う(toggleHiddenFiles / toggleChangedFilesOnly と同型)。
- SidebarNavigatorHost に必須メソッド gitStatusDidApply() を追加し、SidebarNavigator.applyGitStatus が accepted のときに呼ぶ。ViewerWindowController がそこで refreshDiff する。onContentReloaded からの直接呼び出しは削除。バッジの全契機(保存・.git/index 変更・キーウィンドウ化・絞り込みトグル)に差分が追従する。
- 設計レビューで出た 2 件を同時に修正: refreshDiff に capabilities.canToggleDiff ガード(契機が増えるため、画像・PDF で git を起こさない)、着地時に diffDisplayPreference.isEnabled の再確認(取得中に OFF にすると古い本文が store に残る)。

## 検証(実測)
- swift test --skip Integration --skip FileWatcherTests: 1065 tests / 150 suites すべて green。
- 修正を戻すミューテーションで、対象の 4 テストが落ちることを確認した(gitStatusDidApply の本体を空に / manager の broadcast を外す / canToggleDiff ガードを外す)。それぞれ「片方のウィンドウのトグルが全ウィンドウの差分に届く」「git 状態が反映されたら差分も取り直す」「差分表示を OFF にすると本文が捨てられる」「差分を出せない状態では取得しない」が失敗。
- swiftlint: main とのベースライン差分は既存違反の行数カウントのみ(ViewerWindowController.swift 882→890、ViewerWindowManager.swift 478→490 / type_body_length 271→275、ViewerWindowControllerTests.swift 554→559)。新規の違反種別・新規ファイルの違反はゼロ。
- swiftformat: 差分なし。

## 注意点
- 新規の 2 テストは detached の utility タスクを経由するため、全スイート並列実行では既定 10 秒のポーリングでは足りない(単体では 0.2 秒、全体実行では 10 秒超)。timeout: testTimeout(fallback: 60) を明示している。
- MockedViewerWindowManager に repositoryRoot: URL? を追加した(既定 nil = 従来どおり git 管理外)。RecordingGitFileIndex がプロトコル要件 repositoryRoot(forFileAt:) を実装する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
差分の更新契機をバッジと同一化した。ウィンドウ間伝搬は ViewerWindowManager.toggleSourceDiff() の全ウィンドウ反映、契機の一本化は SidebarNavigatorHost の必須メソッド gitStatusDidApply()(外すとコンパイルが通らない)で担保。設計レビュー由来の 2 件(差分を出せない種別での git 起動、取得中に OFF にしたときの残留)も同時に修正。swift test 1065 件 green、ミューテーションで対象 4 テストが落ちることを確認、swiftlint はベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
