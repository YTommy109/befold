---
id: TASK-310
title: フォルダー階層を降りたとき、一番上の項目をサイドバーで選択状態にする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-05 02:32'
updated_date: '2026-08-05 06:36'
labels: []
dependencies: []
priority: medium
ordinal: 508000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 SidebarNavigator.navigateToFolder(_:)(SidebarNavigator.swift:314-332)は、上位フォルダーへ移動したとき以外(下位・横移動)は selection = nil にしている(:328)。これは task-61 で入れた意図的な設計で、選択を空にすることで PreviewTargetResolver.resolve(PreviewTargetResolver.swift:37-53)が selection == nil を「現在ディレクトリの一覧をプレビューに出す」と解釈する仕組み(:44-45)になっている。

今回の要望はフォルダー階層を降りたとき、サイドバーの選択(ハイライト)を一番上の項目に当てておいてほしいというもの。ただしユーザー確認の結果、プレビューエリアの挙動はフォルダー一覧表示のままでよく、選択した項目のファイル内容を自動で開く(task-61 の巻き戻し)ことは想定していない。

そのため単純に selection を一番上の項目の URL に差し替えるだけでは、PreviewTargetResolver が非 nil の selection をファイルエントリとして拾い、意図せずそのファイルをプレビューへ出してしまう(:46-52)。サイドバーの選択(ハイライト・キーボード操作の起点)と、プレビュー対象を決める判定とを分離する設計変更が必要になる見込み。

関連: TASK-309(フォルダー再訪時に直前の選択を復元する)とは独立に成立するが、組み合わせる場合は「TASK-309 の記憶があればそれを優先し、無ければ一番上の項目を選択する」という関係になる想定。実装順序に技術的な依存はない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォルダー階層を降りた(または横移動した)直後、サイドバーの一覧で一番上の項目が選択(ハイライト)状態になっている
- [x] #2 一番上の項目が選択されていても、プレビューエリアはそのファイルの中身ではなく、現在ディレクトリの一覧(フォルダーリスティング)を表示したままである(task-61 の挙動を壊さない)
- [x] #3 選択された一番上の項目に対して矢印キー等のキーボード操作がそのまま使える
- [x] #4 一覧が空のフォルダーへ移動したときは、現状同様に何も選択されない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
0. 単純化の検討: 「選択なし=一覧を出す」という現在の含意を保ったまま要件を満たす方法（ハイライト専用の別状態をサイドバー側だけに持つ／自動選択かどうかを導出で当てる）を検討したが、要件は今まさに一致している 2 状態（ハイライトの有無 / プレビューが一覧かファイルか）を分けることそのものなので、状態ゼロでは実現できない。最小の追加は Bool 1 つで、しかも「選択の書き込み」という単一の絞り込み点で必ず倒れる形にできる。導出点は PreviewTargetResolver 1 箇所のまま保つ。

1. PreviewTargetResolver.resolve に presentsDirectoryListing: Bool を足し、true なら選択の中身に関わらず .folder(currentDirectory) を返す（先頭で短絡）。導出は引数だけで決まる純関数のまま。
2. FileListModel に private var presentsDirectoryListing を追加（didSet は付けず、previewTarget から読む）。selection の setter で false にしてから storedSelection を書く（= 通知は従来どおり 1 回）。フォルダー移動用に selectPresentingDirectoryListing(_:) を足し、pathKey とフラグ true を先に置いてから storedSelection を書く（こちらも通知 1 回）。
3. FileListModel に一覧の先頭行（.parentNavigation を除く visibleEntries の先頭）を返す導出を足す。'..' は移動手段であって項目ではなく、選ぶと Enter が上へ戻る操作になってしまうため除外する。フィルターは移動をまたいで残るので entries ではなく visibleEntries を見る。
4. SidebarNavigator.navigateToFolder の else 側（下位・横移動）を selection = nil から selectPresentingDirectoryListing(先頭行) に変える。上位移動側（直前の子フォルダーを選ぶ）は変えない。
5. テスト: PreviewTargetResolverTests にフラグの短絡を、SidebarNavigatorFolderNavigationTests に「降りたら先頭が選択される / それでも previewTarget は移動先ディレクトリの一覧のまま / 空フォルダーでは選択なし / その後ユーザーが選び直すとフラグが倒れて .file になる」を追加。既存の navigateToChildDoesNotAutoSelect・navigateToChildWithoutFilesClearsSelection は本タスクで意図的に変わる挙動なので書き換える。TDD で先に落ちることを確認してから実装する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: プレビュー対象の導出は PreviewTargetResolver 1 箇所のまま、引数に presentsDirectoryListing を足して短絡させた。FileListModel 側は同名の private フラグ 1 つで、selectPresentingDirectoryListing(_:) だけが立て、selection の setter が必ず倒す（選択の書き込みは全経路がこの setter を通るので、クリック・キー操作・履歴適用・一覧更新の各呼び出し元に後始末を配らずに済む）。両方の書き込み経路ともフラグ・pathKey を先に置いてから storedSelection を書き、提示対象の通知が 1 回に収まる順序にした。

判断: 自動選択の対象からは .parentNavigation（'..'）を外した。選ぶと Enter や → を押した利用者が今降りてきた階層へ押し戻されるため。絞り込みは移動をまたいで残るので entries ではなく visibleEntries の先頭を採る。

副次的に見つかった点: FileListFilter.presentedPathKey（git 絞り込みで提示中の行だけ残す仕組み）を選択に直結させたままだと、フォルダーへ降りるたび未変更の先頭行が 1 件だけ「変更のみ表示」に残った（SidebarNavigatorListingCoherenceTests が実際に落ちて検出）。presentedPathKey は「いま提示している行」であり、一覧を提示している間は該当行が無いのが正しいので、フラグが立っている間は nil を渡すようにした。

検証: swift test 全体 1121 tests / 164 suites パス。新規テストが本当に効いていることを、FileListModel の 2 点（setter でフラグを倒さない / フラグを立てる順序を逆にする）を一時的に変異させて確認し、対応する 3 テストが落ちることを実測した。swiftlint は変更した 4 ファイルに新規警告なし（既に出ている SidebarNavigator+History.swift の opening_brace と FileListView.swift の type_body_length は未変更ファイル由来）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーのハイライトとプレビュー対象を分離し、フォルダー階層を降りた（横移動も含む）ときに一覧の先頭行を選択状態にした。PreviewTargetResolver に presentsDirectoryListing を足して短絡させ、FileListModel の selectPresentingDirectoryListing(_:) が立てて selection の setter が倒す形にしたので、選択の書き込み 1 箇所で必ず解除される。'..' 行は自動選択の対象から外した。プレビューは移動先ディレクトリの一覧のままで（TASK-61 の挙動を維持）、続けて矢印キー・Enter をハイライトの位置から使える。空フォルダーでは従来どおり選択なし。swift test 全 1121 件パス、および実装を一時的に変異させて新規テストが落ちることを実測して検証した。
<!-- SECTION:FINAL_SUMMARY:END -->
