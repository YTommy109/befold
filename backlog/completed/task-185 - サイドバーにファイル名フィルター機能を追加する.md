---
id: TASK-185
title: サイドバーにファイル名フィルター機能を追加する
status: Done
assignee: []
created_date: '2026-07-28 14:04'
updated_date: '2026-07-30 09:56'
labels:
  - frontend
dependencies: []
ordinal: 262000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーのファイル一覧を、名前のワイルドカードパターンで絞り込めるようにする。フォルダ階層は辿らず現在フォルダの直下アイテム(ファイルとサブフォルダ)のみを対象とする。正規表現は使わず、* と ? のワイルドカードのみサポートする。多数のファイルがあるフォルダで目的のファイルへ素早く到達できるようにするのが狙い。

## UI
- サイドバーヘッダーにフィルター開閉アイコン(例: line.3.horizontal.decrease.circle)を並び替え・非表示トグルの隣に追加する。
- クリックまたは Cmd+F でヘッダー直下に検索フィールドを表示し、再押下または esc で閉じてフィルターを解除する。
- フィルター文字列が有効なときはアイコンを強調表示する。

## マッチ規則
- 大文字小文字を無視した部分一致。内部的に入力を *<入力>* にラップして fnmatch 相当で評価する。
- ワイルドカードは * (0文字以上) と ? (任意1文字) のみ。[...] などその他の glob 構文や正規表現は非対応。

## 対象・スコープ・保持
- 対象は現在フォルダ直下のファイルとサブフォルダの名前。階層は辿らない。
- 親ディレクトリ(..)は常に表示しフィルター対象外とする。
- フォルダ移動後もフィルター文字列は保持する(クリアしない)。
- セッション保存はしない(アプリ再起動時は空)。
- 全件除外された場合は既存の空表示(ContentUnavailableView)を流用する。

## 実装方針
- マッチ判定は BefoldKit に純粋関数(例: WildcardMatcher)として切り出し、ユニットテスト対象とする。
- FileListModel にフィルター文字列と可視状態を持たせ、元のエントリ一覧は保持したまま算出側で絞り込む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 esc または再押下でフィールドを閉じフィルターが解除される
- [x] #2 * と ? のワイルドカードが機能し、大文字小文字を無視した部分一致で絞り込まれる
- [x] #3 正規表現や [...] など * ? 以外の glob 構文は特殊解釈されない
- [x] #4 現在フォルダ直下のファイルとサブフォルダ名がフィルター対象で、階層は辿らない
- [x] #5 親ディレクトリ(..)はフィルターに関わらず常に表示される
- [x] #6 フォルダ移動後もフィルター文字列が保持される
- [ ] #7 アプリ再起動後はフィルターが空に戻る
- [x] #8 マッチ判定ロジックが BefoldKit の純粋関数として切り出され、ユニットテストがある
- [ ] #9 サイドバーヘッダーのアイコンでフィルターフィールドを開閉できる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit/WildcardMatcher.swift を追加(PathRelativizer.swift と同じ enum+static func スタイル)。
   - `public static func matches(pattern: String, in name: String) -> Bool`
   - 入力を `*<pattern>*` にラップし、`*`→`.*`, `?`→`.` 以外の正規表現メタ文字は全て
     エスケープしてから NSRegularExpression(caseInsensitive) で評価する。
   - befoldTests/WildcardMatcherTests.swift を追加(空文字列=全件一致、大文字小文字無視、
     `*`/`?` の挙動、`[...]` などその他 glob 構文が特殊解釈されないことを検証)。

2. FileListModel に `var filterText: String = ""` と `var isFilterActive: Bool = false` を追加。
   showHiddenFiles とは異なり Preference 化はせず、モデルのプレーンな値のまま
   (SidebarNavigator が entries を差し替えても保持され、アプリ再起動時は初期値に戻る)。
   `entries` はディスク由来の一覧を保持したまま、`visibleEntries`(computed)で
   WildcardMatcher により lastPathComponent をフィルタする。ただし `.kind == .parentNavigation`
   の行は filterText に関わらず常に含める。

3. FileListView:
   - entryList の List、空表示判定、selectNext/selectPrevious/enterSelected/navigateToParent を
     model.entries から model.visibleEntries に差し替える(表示中の行だけをキーボード操作対象にする)。
   - navigationHeader に3つ目のアイコンボタン(line.3.horizontal.decrease.circle /
     .fill、filterText が空でなければ強調表示)を追加し、isFilterActive をトグルする。
     Cmd+F は割り当てない(既存のページ内検索と衝突するため、アイコンクリックのみ)。
   - isFilterActive==true のとき navigationHeader 直下に検索用 TextField を表示
     (QuickOpenView の @FocusState + onAppear フォーカスパターンを踏襲)。
     `.onKeyPress(.escape)` およびアイコン再押下でフィールドを閉じ、同時に
     filterText を空にする(「解除」)。

4. Localizable.xcstrings に sidebar.filter.show / sidebar.filter.hide(アイコンの help)、
   必要ならプレースホルダー文言を en/ja で追加(既存 sidebar.hiddenFiles.* と同じ形式)。

5. 手動確認: 多数ファイルのフォルダで * / ? 入力、フォルダ移動後の保持、esc/再押下での解除、
   .. の常時表示、全件除外時の ContentUnavailableView 再利用を確認する。

備考: Cmd+F はページ内検索(ViewerWindowController.find)と衝突するため、ユーザーと協議の上
AC#1 からショートカット要件を除外し、アイコンクリックのみに変更済み。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査の結果、Cmd+F は既に ViewerWindowController.find(_:) (ページ内検索/WKWebView JS find bar) に割り当て済みと判明。ユーザーと協議し、フィルター開閉はヘッダーアイコンのクリックのみとし、Cmd+F 割り当ては行わない方針に決定(AC#1 を更新)。

自動テストで検証: WildcardMatcherTests(*/? 動作・大文字小文字無視・[...] 等の非対応構文がリテラル扱いされること)、FileListModelFilterTests(visibleEntries の絞り込みと parentNavigation の常時表示)、SidebarNavigatorIntegrationTests(navigateToFolder 後も filterText が保持されること)。swift test 実行で 868 件全て成功。AC#1・#9(アイコン開閉・esc解除)と AC#7(再起動後に空へ戻ること)は UI/実行時挙動でありプロジェクト規約(WebView/GUI層は自動テスト対象外・リリース前手動チェック)に従い自動テスト未実施。実機起動での確認を試みたが、befold は Bundle Identifier が同一のため実行中の本番アプリ(session restore 含む UserDefaults)を共有してしまうと判明し、ユーザー実セッションを上書きするリスクを避けるため中断(ユーザーと協議の上、自動テストでの確認範囲で完了とする方針に決定)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーにファイル名フィルターを実装した。BefoldKit に WildcardMatcher(*/? のみ対応・大文字小文字無視の部分一致)を純粋関数として追加し、単体テストを作成。FileListModel に filterText/isFilterActive と、entries を保持したまま算出する visibleEntries(parentNavigation は常に含む)を追加。FileListView のキーボード操作・空表示判定・List を visibleEntries 基準に変更し、ヘッダーに3つ目のアイコン(line.3.horizontal.decrease.circle)でフィルター欄を開閉する UI を追加(Cmd+F は既存のページ内検索と衝突するため、ユーザーと協議しアイコンクリックのみに変更、AC#1 を更新済み)。Localizable.xcstrings に sidebar.filter.* を en/ja で追加。検証: swift test で 868 件全て成功(WildcardMatcherTests, FileListModelFilterTests, 既存 SidebarNavigatorIntegrationTests への追加テストを含む)。UI 層(アイコン開閉・esc解除・再起動後リセット)は自動テスト対象外(プロジェクト規約)のため、リリース前の手動確認が必要。
<!-- SECTION:FINAL_SUMMARY:END -->
