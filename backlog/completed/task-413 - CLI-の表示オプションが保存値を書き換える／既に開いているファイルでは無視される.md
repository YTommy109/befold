---
id: TASK-413
title: CLI の表示オプションが保存値を書き換える／既に開いているファイルでは無視される
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 07:26'
updated_date: '2026-08-10 10:51'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 501000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
openViewer への入口が枝ごとに違う扱いをしており、同じフラグが経路によって「保存値を汚す」「黙って捨てられる」の両方に転ぶ。

1. 保存値の書き換え（ViewerWindowManager.swift:192）: applyDisplayOverrides は CLI の --source / --preview を controller.setDisplayMode 経由で適用するが、setDisplayMode は ViewerWindowController.swift:741 で perFileState.displayMode.setDisplayMode(_:for:) を呼び保存する。パスなしの `befold --source` を打つと、開いている全ファイルの保存済み表示モードが恒久的に上書きされ、以後そのファイルはフラグなしでも source で開く。同じループの隣にある store.applyShowLineNumbersOverride は保存を避けるために存在し、ViewerWindowController.init（:330）も「保存値は書き換えない(この起動限りの上書き)」というコメント付きで非永続の applyDisplayMode を使う。同じフラグがパス指定の有無で逆の永続性になっている。

2. オプションの取りこぼし（ViewerWindowManager.swift:233）: .currentTab の重複抑止は NSApp.activate() / existing.focusWindow() / return だけで、options も forceSidebarVisible も読まない。foo.md を開いた状態で `befold --line-numbers foo.md`（--source / --sidebar / --sort も同様）を打つと、窓が前面に来るだけでフラグは適用されず通知もない。openViewer の doc コメント自身が「options を丸ごと受けるのは途中でオプションを落とさないため」と書いている。

3. 開く順序の非決定（AppDelegate.swift:337）: showOpenPanel は allowsMultipleSelection = true（:329）なのに、完了ブロックで URL ごとに openViewer(for:) を呼ぶ。この 1 引数オーバーロード（:263）は 1 件ごとに Task を張り、その中で Task.detached のファイル解決を待つため、5 件選ぶとウィンドウとキーウィンドウの順序が任意になる。application(_:open:)（:227）と openPaths（:290）は「渡された順にウィンドウが出るよう 1 本の Task で逐次に開く」と明記して 1 本の Task でループしており、Open パネル経路だけがその不変条件から外れている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 パス無しで表示フラグ（--source/--preview/--line-numbers/--no-line-numbers/--sidebar/--no-sidebar/--sort）を渡すと CLI がバリデーションエラーで終了し、アプリへ転送しない
- [x] #2 パス無しの --hidden-files/--no-hidden-files は従来どおりアプリ全体設定として有効（エラーにしない）
- [x] #3 既に開いているファイルを対象に CLI フラグを渡したとき、そのウィンドウへフラグが適用される（--line-numbers / --source / --sidebar / --sort）
- [x] #4 CLI 由来の表示モード上書きは、新規ウィンドウ・既存ウィンドウのどちらでも保存値（DisplayModeStore）を書き換えない
- [x] #5 Open パネルで複数選択したとき、選択順にウィンドウが開く
- [x] #6 オプション適用が ViewerWindowManager.openViewer の単一経路に一本化され、applyDisplayOverrides は撤去される
- [x] #7 ADR 0002 の遷移表（CLI --source/--preview の行）を新しい規則へ更新する
- [x] #8 上記をユニットテストで担保する（経路を増やしたら落ちる形にする）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー（/review-design）で確定した論点

F1 判定の真実の源: バリデーション述語を options != CLIOpenOptions() で書かない（--hidden-files 単独を誤って弾く）。CLIOpenOptions に明示的な requiresPaths を置き、CLIAppLauncher:69,91 の「転送するか」の比較とは別の述語であることを doc で固定する。
F2 消費経路の全列挙: .currentTab の既存ウィンドウ枝は options だけでなく forceSidebarVisible も落としている（ViewerWindowManager.swift:247-251）。options だけ直すと同型の穴が残る。
F3 兄弟判断: 同一ファイルが複数窓で開いている場合（TASK-412）、適用先は前面化する controllers[key]?.first の 1 窓に揃える。
F4 既存の不変条件との衝突: ADR 0002:160-163「降格規則は supportedDisplayMode の 1 箇所」に対し、現行 init は CLI override を降格せず applyDisplayMode している（ViewerWindowController.swift:231-232。降格されるのは restoredDisplayMode 経由の保存値だけ）。新規・既存の両方を supportedDisplayMode 経由へ揃える（befold --source image.png が .source にならなくなる挙動変更を含む）。
F5 決めた粒度を守らせるもの: 「適用は 1 経路」を doc で書いても守られない。CLIOpenOptions のフィールドが増えたら落ちる形（Mirror でのフィールド数固定 + 全フィールド非 nil の適用テスト）を付ける。
F6 測るものと守るもの: AppDelegate を生成する単体テストは 0 件（実測）。showOpenPanel を直しても測れないため、逐次オープンのループを注入可能なヘルパーへ切り出してそこに順序テストを書く。
F7 新しい状態の表示: CLI エラーという新状態の文言に、パスを要する対象フラグを列挙する。事実と食い違うドキュメントは ADR 0002:154-155 / docs/dev/cli-launch.md:37,42,58,169-170 / README.md:57-59 の 3 ファイル。
F8 ライフサイクル: openPaths のパス空分岐撤去後も --hidden-files 単独は setHiddenFiles して return で成立（CLIAppLauncher は options 非既定なら転送する）。NSApp.activate() の位置は変えない。
F9 高頻度経路: 該当しない（CLI オープンは低頻度、追加分は既存ウィンドウ 1 個への同期適用のみ）。
F10 非同期の世代管理: 該当しない（適用は MainActor 上の同期処理）。解決中に窓が閉じられた場合は controllers[key] が nil になり新規オープン枝が吸収する。
F11 スコープ判断: --check/--bookmark と表示フラグの併用も現状は黙って無視される（BefoldCLICommand.swift:60-62）。同型の「黙って捨てる」なので今回のバリデーションに含める。

## 実装手順

1. CLIOpenOptions に requiresPaths（showHiddenFiles 以外のいずれかが非 nil）を追加。BefoldCLICommand.validate() に (a) paths 空 + requiresPaths、(b) check/bookmark + requiresPaths の 2 条件を足す。
2. ViewerWindowManager.applyDisplayOverrides を撤去し、AppDelegate.openPaths のパス空分岐を撤去する。
3. openViewer の .currentTab 既存枝で、前面化の前に applyOpenOptions(options, forceSidebarVisible:to:) を呼ぶ。表示モードは supportedDisplayMode を通した上で applyDisplayMode（非永続）。init 側も同じ降格へ揃える。
4. 複数 URL を逐次に開くループをヘルパーへ切り出し、application(_:open:) / openPaths / showOpenPanel の 3 経路を合流させる。
5. ADR 0002 の遷移表・docs/dev/cli-launch.md・README.md を更新する。
6. テスト: CLI バリデーションの表 + Mirror のフィールド数固定 + 既存ウィンドウへの全フラグ適用 + 表示モード保存値が不変 + 逐次オープンの順序。
7. 検証: swift test / swiftlint ベースライン差分ゼロ / markdownlint-cli2。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針決定（ユーザー確認済み）: 起票時の AC #1「パス無しの --source が保存値を書き換えない」は、ADR 0002 の遷移表 155 行目「CLI --source/--preview（パス無し・既存ウィンドウ）→ 永続化する／明示的なユーザー操作として扱う」（2026-08-08 コミット 75c9a6a で根拠付きで追記）と真逆だったため、着手前にユーザーへ確認した。

結論は「パス無しの表示フラグは CLI エラーにする」。範囲は表示フラグ全部（--source/--preview/--line-numbers/--sidebar/--sort）で、--hidden-files はアプリ全体設定なので従来どおりパス無しでも有効。これに伴い ViewerWindowManager.applyDisplayOverrides（TASK-82 で入ったパス無し全窓適用）は撤去し、ADR 0002 の 154/155 行目も書き換える。AC は上記の決定に合わせて全面的に差し替えた。

## 実装結果

1. パス必須の判定: CLIOpenOptions.requiresPaths（showHiddenFiles 以外のいずれかが非 nil）を追加し、BefoldCLICommand.validate() が (a) パス無し、(b) --check/--bookmark 併用 の 2 つを ValidationError にする。設計レビュー F1 のとおり options != CLIOpenOptions() では書いていない（--hidden-files 単独を弾いてしまうため）。CLIAppLauncher の同形の比較は「転送するか」の別判定であることを doc で固定した。
2. applyDisplayOverrides を撤去し、AppDelegate.openPaths のパス空分岐も撤去。
3. openViewer の .currentTab 既存枝を reopenExistingWindow へ置き換え、表示オプションと forceSidebarVisible（F2）を適用してから前面化する。適用先は前面化する 1 窓（F3）。
4. 表示モードは applyCLIDisplayMode(isSourceMode:) の 1 経路へ集約し、init もそこを通す。降格規則 supportedDisplayMode を必ず通すようにした（F4。befold --source image.png が .source にならなくなる挙動変更を含む）。
5. 複数 URL のオープンは SequentialOpener へ集約し、application(_:open:) / openPaths / showOpenPanel の 3 経路を AppDelegate.openSequentially へ合流させた（F6）。
6. ドキュメント: ADR 0002 の遷移表 2 行と永続化規則、docs/dev/cli-launch.md（新設「表示オプションはパスを要する」節と openPaths の記述）、README.md を更新。ViewerWindowController+Presentation.swift の setDisplayMode に残っていた「パス無し befold --source」への言及も削除した。
7. 付随の同期: SessionRestorer.restoreLastSession(options:) の doc が「パス無し CLI 起動の並び順・行番号・ソースモードがここへ届く」と書いていたが、その経路は存在しなくなった。本番の呼び出し元は既定値のみで呼ぶ。options をフィールド単位で手写しせず openViewer へそのまま渡す形は、経路ごとの取りこぼし防止として維持し、テスト名だけ実態へ合わせた。

## 検証（すべて実測）

- swift test（Integration 込み）: 1385 tests / 202 suites すべて通過。
- 修正前に失敗を確認したうえで実装した: CLI 側は requiresPaths 未実装のコンパイルエラー、GUI 側は 9 件の失敗（既存ウィンドウへ未適用・保存値の書き換え・降格なし）。
- xcodebuild build -scheme befold: BUILD SUCCEEDED（新規 3 ファイル追加後に xcodegen generate 実行済み）。
- swiftformat: fix モードで整形済み、--lint で 0 件。
- swiftlint: origin/main を git archive で展開して同一 config で比較。件数 51 件で同一、ルール集合・対象ファイルとも一致し真の新規はゼロ（AppDelegate は 501→495 行へ減、ViewerWindowManager は 526→536 行へ増だが、いずれも変更前から出ている既存違反）。
- markdownlint-cli2: 67 ファイルで 0 issues。

## 担保（破れたら落ちるもの）

- BefoldCLIOptionValidationTests.optionFieldsAreEnumeratedExhaustively が CLIOpenOptions のフィールド集合を固定する。フィールドを足すと落ち、requiresPaths とウィンドウへの適用の双方の更新を強制する（F5）。
- ViewerWindowManagerDisplayOverridesTests が、新規ウィンドウと既存ウィンドウで同じ結果になること・保存値を書き換えないこと・降格が両経路で効くことを固定する。
- SequentialOpenerTests は遅い先頭要素が後続に追い越されないことを見る。並行実行へ書き換えると落ちる（F6）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI の表示オプションが経路ごとに違う扱いになっていた問題を、適用経路の一本化で解消した。パスを伴わない表示フラグは CLIOpenOptions.requiresPaths を見て CLI のパース段階でエラーにし（--hidden-files はアプリ全体設定のため対象外）、開いている全ウィンドウへ適用していた applyDisplayOverrides を撤去した。既に開いているファイルを指定した場合は openViewer の重複抑止枝で表示オプションと forceSidebarVisible を適用してから前面化する。表示モードは applyCLIDisplayMode の 1 経路へ集約し、新規・既存のどちらでも保存値を書き換えず降格規則を通す。複数 URL のオープンは SequentialOpener へ集約し、Open パネルの複数選択も選択順に開く。ADR 0002・docs/dev/cli-launch.md・README.md を新しい規則へ更新済み。swift test 1385 tests / 202 suites 通過、xcodebuild BUILD SUCCEEDED、swiftlint はベースライン差分ゼロ、markdownlint 0 issues。
<!-- SECTION:FINAL_SUMMARY:END -->
