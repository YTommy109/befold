---
id: TASK-265
title: ファイル数の多いフォルダーでサイドバーがフリーズする（URL をリスト ID にしたことによる正規化ハッシュ）
status: To Do
assignee: []
created_date: '2026-08-03 12:32'
updated_date: '2026-08-03 12:46'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 320000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーでファイル数の多いフォルダー（再現例: 本リポジトリの backlog/tasks、343 件）へ移動するとレインボーカーソルが出て操作できなくなる。

## 実測で特定した原因（2026-08-03・dev ビルドを sample で採取）

メインスレッドのサンプル 4530 中 3078 が SwiftUI の OutlineListCoordinator.diffRows 配下で、その大半が

  ForEachState.item(at:offset:) → Dictionary.lookup → 'protocol witness for Hashable._rawHashValue in conformance URL'
  → _StringGutsSlice._normalizedHash → -[__NSCFString characterAtIndex:]

に落ちている。sample のトップ・オブ・スタック上位も _CFStringCheckAndGetCharacterAtIndex(955) / -[__NSCFString characterAtIndex:](516) / _withNFCCodeUnits(378) が占める。

つまり真因は一覧の構築コストでも NSWorkspace のアイコン取得でもない。FileListEntry.id が URL（FileListEntry.swift の 'var id: URL { url }'）で、SwiftUI の ForEach が行 ID を辞書キーにするたびに URL の Hashable が走り、**パス文字列全体の Unicode 正規化**が発生する。しかも DirectoryLister が FileManager 経由で作った URL は NSString 裏打ちのため、正規化が 1 文字ずつ ObjC 呼び出し（characterAtIndex:）になる遅い経路を通る。ファイル名が日本語（非 ASCII）だと正規化が短絡できず、コストがそのまま出る。

## 補助的な実測（343 件、辞書へ挿入 + 全件参照を 1 パスとする）

- FileManager 由来の URL をキーにする: 17.86 ms/パス
- 同じパスから作り直した（native String 裏打ちの）URL をキーにする: 0.36 ms/パス → **約 50 倍差**
- pathKey(String)をキーにする: 10.54 ms/パス（macOS のファイル名は NFD なので String でも正規化は走る）

参考: 同じ 343 件で NSWorkspace.icon(forFile:) 全件は 41 ms、正規化パスキーの算出は 12 ms。1 回きりのこれらではなく、**更新のたびに何百回も走るハッシュ**が支配的。

## 検討の出発点（実装は要設計）

1. FileListEntry の ID を「ハッシュが安く、リフレッシュをまたいで安定」な型にする。単純に pathKey(String) へ替えるだけでは上表のとおり 10.54 ms 残るので不十分。構築時にハッシュ値を 1 度だけ計算して保持し、hash(into:) はその値だけを使う ID 型（== はパス文字列比較のまま）にするのが本命。
2. DirectoryLister で URL を native String から作り直し、NSString 裏打ちを断ち切る（上表 0.36 ms の経路に乗せる）。1 と併用でき、単体でも効く見込み。
3. いずれも FileListEntry.ID = URL を前提にした箇所（FileListModel.selection / FileListView のキー操作・選択復元 / SidebarNavigator の選択維持・PreviewTargetResolver / FolderListingView）に波及するため、選択維持の回帰テストを合わせて用意する。

## 補足

- 本件は task-263（フォルダー行の Git バッジ）とは独立。id: URL は以前からで、sample のホットパスに git 状態の写像は現れない。
- 非 ASCII 名が引き金になるため、英名だけのフォルダーでは同じ件数でも軽く見えることがある。再現確認は日本語名を含むフォルダーで行うこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーで 300 ファイル規模のフォルダー（例: backlog/tasks）へ移動しても、レインボーカーソルが出ずに一覧が表示される
- [ ] #2 移動後のスクロール・選択・キーボード操作でもメインスレッドが目に見えて詰まらない
- [ ] #3 改善前後を同一フォルダーで実測し、メインスレッド占有時間の比較値を Notes に残す
- [ ] #4 選択状態の維持（フォルダー移動・リネーム追従・戻る/進む）が従来どおり動作し、既存テストが green
- [ ] #5 ファイル名が非 ASCII（日本語）でも ASCII でも一覧・選択が正しく機能する
- [ ] #6 backlog のように直下の項目数が少ないフォルダーでも、カーソルを大量ファイルのフォルダー行（tasks）に乗せて通過する操作が待たされない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 2 つ目の再現経路（2026-08-03 追記・原因は同一）

フォルダーに入らず、カーソルを乗せて通過するだけでも遅い。選択が変わると ViewerContentView が PreviewTargetResolver 経由で .folder(...) と判定し、プレビュー領域に FolderListingView を描画する（ViewerContentView.swift:79-86）。これは FileListEntryRow を並べた同じ List で、行 ID も同じ FileListEntry.id = URL なので、サイドバー側と同じ diffRows → ForEachState → URL の正規化ハッシュを踏む。行に乗せるたびにその中身ぶんのリストを 1 つ組み立てるため、次の行へフォーカスが移るのが待たされる。

したがって修正対象は FileListEntry の ID 型（および URL の裏打ち）であり、サイドバー・FolderListingView の両方が同時に直る見込み。逆に、サイドバー側だけを最適化する対処では本経路が残る。

ディレクトリ列挙自体は FolderListingView の .task から listEntriesAsync でメイン外に出ており無関係（343 件で列挙 12ms + ソート 10ms 程度）。

補足: この操作そのものの sample 採取はスクリプトからのキー入力がサイドバーに届かず失敗した。根拠は 343 行リストの実測サンプル（Description 参照）と上記コード経路。
<!-- SECTION:NOTES:END -->
