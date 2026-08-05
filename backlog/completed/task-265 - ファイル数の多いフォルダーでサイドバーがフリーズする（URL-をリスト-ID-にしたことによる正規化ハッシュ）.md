---
id: TASK-265
title: ファイル数の多いフォルダーでサイドバーがフリーズする（URL をリスト ID にしたことによる正規化ハッシュ）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-03 12:32'
updated_date: '2026-08-03 13:32'
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
- [x] #1 サイドバーで 300 ファイル規模のフォルダー（例: backlog/tasks）へ移動しても、レインボーカーソルが出ずに一覧が表示される
- [x] #2 移動後のスクロール・選択・キーボード操作でもメインスレッドが目に見えて詰まらない
- [x] #3 改善前後を同一フォルダーで実測し、メインスレッド占有時間の比較値を Notes に残す
- [x] #4 選択状態の維持（フォルダー移動・リネーム追従・戻る/進む）が従来どおり動作し、既存テストが green
- [x] #5 ファイル名が非 ASCII（日本語）でも ASCII でも一覧・選択が正しく機能する
- [x] #6 backlog のように直下の項目数が少ないフォルダーでも、カーソルを大量ファイルのフォルダー行（tasks）に乗せて通過する操作が待たされない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 実測で方針を決める（URL 再構築のみで足りるか、ID 型新設が要るか）
2. 足りるなら URL.nativeBackedFileURL を BefoldKit に追加し、FileListEntry.init で適用（変更点 1 箇所）
3. FileManager 由来 URL でも native 裏打ちかつ元 URL と等価になるテストを先に書く
4. 全テスト green・swiftlint ベースライン差分ゼロ・xcodebuild 成功を確認
5. dev ビルドで backlog/tasks の移動・通過を手で確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 2 つ目の再現経路（2026-08-03 追記・原因は同一）

フォルダーに入らず、カーソルを乗せて通過するだけでも遅い。選択が変わると ViewerContentView が PreviewTargetResolver 経由で .folder(...) と判定し、プレビュー領域に FolderListingView を描画する（ViewerContentView.swift:79-86）。これは FileListEntryRow を並べた同じ List で、行 ID も同じ FileListEntry.id = URL なので、サイドバー側と同じ diffRows → ForEachState → URL の正規化ハッシュを踏む。行に乗せるたびにその中身ぶんのリストを 1 つ組み立てるため、次の行へフォーカスが移るのが待たされる。

したがって修正対象は FileListEntry の ID 型（および URL の裏打ち）であり、サイドバー・FolderListingView の両方が同時に直る見込み。逆に、サイドバー側だけを最適化する対処では本経路が残る。

ディレクトリ列挙自体は FolderListingView の .task から listEntriesAsync でメイン外に出ており無関係（343 件で列挙 12ms + ソート 10ms 程度）。

補足: この操作そのものの sample 採取はスクリプトからのキー入力がサイドバーに届かず失敗した。根拠は 343 行リストの実測サンプル（Description 参照）と上記コード経路。

## 修正方針と実測（2026-08-03）

### 単純化の検討
Description の本命案（事前計算ハッシュの ID 型）は FileListModel.selection / SidebarNavigator / PreviewTargetResolver / FolderListingView へ波及する。先に案 2（URL の裏打ちを native String に直す）を実測したところ十分な効果があり、変更点が FileListEntry.init の 1 箇所で済むためこちらを採用した。

### 実測（本リポジトリ backlog/tasks・344 件、辞書へ挿入＋全件参照を 1 パス、5 回の最良値）
| キー | 時間/パス |
|---|---|
| FileManager 由来 URL（修正前） | 10.34 ms |
| native 裏打ちに直した URL（修正後） | 0.49 ms |
| path String そのまま | 5.84 ms |
| 事前計算ハッシュ ID（不採用案） | 0.21 ms |

修正前後で **約 21 倍**。ID 型新設まで行っても 0.49→0.21 ms の差にとどまるため、波及に見合わないと判断した。

### 実装
- BefoldKit/URL+NormalizedPathKey.swift に `nativeBackedFileURL` を追加（既に連続 UTF-8 なら自身を返す。isDirectory: hasDirectoryPath で末尾スラッシュの意味を保つ）
- FileListEntry.init で `self.url = url.nativeBackedFileURL`。id / pathKey / == の意味は変わらないため呼び出し側の変更は不要で、サイドバーと FolderListingView が同時に直る
- 判明した前提: URL(fileURLWithPath:) で作った URL のパスは連続 UTF-8 になる。非連続になるのは FileManager 列挙由来のものだけで、テストは実ファイルシステム（日本語名）で前提ごと検証している

### 確認済み
- swift test 全体 green（1005 tests / 150 suites）
- swiftlint: 変更ファイルの警告は既存の identifier_name('id') のみでベースライン差分ゼロ
- xcodebuild build -scheme befold 成功

### 残: GUI での手動確認（AC #1 / #2 / #6）

## GUI 実測（2026-08-03・sample 1ms・修正前後を同一手順で採取）

修正前の実測は、同じ手元で FileListEntry.init の 1 行だけを修正前に戻して Debug ビルドし直して採った（Description の起票時サンプルとは別に取り直した比較値）。

### シナリオ A: backlog/tasks（344 件）を開き、下矢印 40 回（AC #1 / #2）
修正後のメインスレッド 3078 サンプル中、待機（mach_msg2_trap）2632 = 85% が idle。diffRows 216（7%）、_normalizedHash 2（0.06%）。レインボーカーソルは出ず、キー入力に追従した。トップ・オブ・スタックからは起票時に上位を占めた _CFStringCheckAndGetCharacterAtIndex / characterAtIndex / _withNFCCodeUnits が消え、最上位は Hasher.combine(bytes:)（native の高速経路）になった。

### シナリオ B: backlog/ でカーソルを tasks 行に乗せて往復（下↑上を 12 往復 = 24 回の選択変更 / 約 3.6 秒）（AC #6）
| | メインスレッド総数 | idle | busy | diffRows | _normalizedHash |
|---|---|---|---|---|---|
| 修正前 | 2737 | 65 (2.4%) | 2672 (97.6%) | 2477 | 1887 (69%) |
| 修正後 | 2774 | 614 (22%) | 2160 (78%) | 1395 | 8 (0.3%) |

本件の原因である URL の正規化ハッシュは 69% → 0.3% で実質消滅した。

### 残るコスト（本件とは別原因）
修正後に残る 78% は SwiftUI の 344 行リスト再構築そのもので、アプリ側の内訳は ViewerWebView.makeNSView 209 サンプル（選択が folder/file で切り替わるたびに WKWebView を作り直している）と FileListEntryRow.body 189。毎秒 6.7 回という機械的な連打での値であり、正規化ハッシュのような支配的ホットスポットは残っていない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileListEntry.init で URL を native 裏打ち（連続 UTF-8）に揃え、SwiftUI の ForEach が行 ID として URL を辞書キーにするたびに走っていた 1 文字ずつの Unicode 正規化を解消した（BefoldKit に URL.nativeBackedFileURL を追加、変更点は init の 1 行）。

検証: 344 件のマイクロベンチで 10.34ms/パス → 0.49ms/パス。GUI は修正前後を同一手順の sample(1ms) で比較し、tasks 行往復シナリオでメインスレッド占有 97.6% → 78%、うち原因である _normalizedHash は 69% → 0.3%。tasks を開いて下矢印 40 回のシナリオではメインスレッドの 85% が idle でレインボーカーソルは出ない。swift test 1005 tests green（FileManager 由来 URL・日本語名の実 FS テストを追加）、swiftlint ベースライン差分ゼロ、xcodebuild 成功。

残コスト（別原因の WKWebView 再生成）は TASK-266 として起票した。
<!-- SECTION:FINAL_SUMMARY:END -->
