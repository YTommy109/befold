---
id: TASK-557.2
title: 負の数の表示と桁区切りを Preferences で切り替えられるようにする
status: To Do
assignee: []
created_date: '2026-08-27 04:20'
updated_date: '2026-08-27 04:25'
labels: []
dependencies:
  - TASK-557.1
parent_task_id: TASK-557
ordinal: 807000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-557.1 で入れた列判定はそのまま使い、その列に対する表示のしかたを app-global の Preferences から選べるようにする。

## 設定項目

| 項目 | 型 | 既定 |
| --- | --- | --- |
| 数値列に桁区切りを入れる | Bool | オン |
| 負の数の表示 | 通常 / ▲ 表記 / 赤字 / ▲ + 赤字 | 通常 |

右寄せは設定にしない（常時。ユーザーが切り替えられなくてよいとの判断）。

## 「金額列」は判定しない

会計慣習の ▲ 表記・赤字は金額に対するものだが、**どの列が金額かをこちらで推測しない**。ヘッダー名の肯定側マッチ（`price` / `金額` 等）は網羅不能で、当てにすると誤爆を増やす方向にしか働かない（TASK-557.1 で肯定側マッチを不採用にしたのと同じ理由）。

代わりに、**preferences そのものが意図を運ぶ**と考える。「負の数の表示」を既定「通常」にしておけば、これを ▲ や赤字に変えるユーザーは自分の扱うファイルが会計データであることを宣言している。したがって適用範囲は TASK-557.1 の第 2 段の列（＝コードとみなせない量の列）すべてでよい。

この設計では気温のような非金額の量の列も ▲ になるが、それは設定をオンにしたユーザーの選択であって実装側の誤判定ではない。責任の所在が違う。

## 設定画面の構造（決定済み）

**タブは導入せず、既存の 1 枚の Form に Section を足す。** 窓の幅を広げ、コードフォントの Section 群と数値表示の Section が見分けられるようにする。

現状の `befold/Viewer/CodeFontSettingsView.swift` は `Form` に Section「コードフォント」「プレビュー」を持ち `.frame(width: 360)` で固定。窓のタイトルは既に汎用の `settings.windowTitle` を使っているのでタイトルの変更は不要。必要なのは次の 3 つ。

1. **型とファイルの改名**: `CodeFontSettingsView` はもうコードフォント専用ではないので `SettingsView`（等）へ改名する。ファイル名も追随させ、置き場は `befold/Viewer/` のままでよいか検討する。ファイルの追加・改名なので `xcodegen generate` を忘れない。
2. **幅を広げる**: `.frame(width: 360)` を広げる。`AppDelegate+HostedPanels.swift` の `.settings` は `resizable: false` なので、幅は固定のまま値だけ変える。
3. **Section の並び**: 現状「コードフォント」→「プレビュー」の順で、プレビューはコードフォントの見本。ここへ数値表示の Section を足すと、フォントの見本が 2 つの機能の間に挟まる。数値表示 Section は「プレビュー」より後ろに置くか、プレビューをフォント Section 側へ寄せるかを実装時に決める。

初期化引数は現状 `preference:` / `onChange:` の 2 つ。数値表示の Preference と、その変更を全窓へ流すコールバックが増える。

## 実装上の前提（調査済み）

- 設定の永続化は `@AppStorage` ではなく、`befold/App/CodeFontPreference.swift` に倣った専用 `@MainActor` Preference 型（UserDefaults 直読み書き + `didSet` 書き戻し）を作り `befold/App/AppStores.swift` に束ねる（ADR 0002）。Preference 型は `@Observable` ではないので、View 側は `@State` を持ち `onChange` で書き戻す write-through 方式に倣う。
- JS への伝達は `BefoldKit/ViewerBridge.swift` の注入スクリプト + `viewer-src` の `_mmdInit*` 受け口。`viewer-src/viewer-globals.d.ts` の `Window` に追記するのが定石。JS 関数名は `ViewerBridge.PlainFunction` に載せると契約テストが実在を検証する。
- 設定変更時の既存窓への即時反映は `befold/App/GlobalDisplayBroadcaster.swift` の `applyCodeFontToAllWindows()` と同型の経路（`ViewerWindowController+SidebarHost` → `WebViewCommandController` → `WebViewDocumentRenderer`）。
- ローカライズは `befold/Resources/Localizable.xcstrings` に `settings.*` 階層で en/ja 両方。キー順のソートし直しはしない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 桁区切りのオン/オフを Preferences から切り替えられ、既定はオン
- [ ] #2 負の数の表示を 通常 / ▲ / 赤字 / ▲+赤字 から選べ、既定は 通常
- [ ] #3 設定を変更すると、既に開いている窓の表示が再読み込みなしで変わる
- [ ] #4 設定値が UserDefaults に永続化され、再起動後も復元される（未設定時は既定値）
- [ ] #5 TASK-557.1 の第 1 段のみの列（コードとみなされた列）には ▲・赤字・桁区切りのいずれも適用されない
- [ ] #6 設定項目のラベルが en/ja 両方でローカライズされている
- [ ] #7 桁区切りのオン/オフを Preferences から切り替えられ、既定はオン
- [ ] #8 負の数の表示を 通常 / ▲ / 赤字 / ▲+赤字 から選べ、既定は 通常
- [ ] #9 設定を変更すると、既に開いている窓の表示が再読み込みなしで変わる
- [ ] #10 設定値が UserDefaults に永続化され、再起動後も復元される（未設定時は既定値）
- [ ] #11 TASK-557.1 の第 1 段のみの列（コードとみなされた列）には ▲・赤字・桁区切りのいずれも適用されない
- [ ] #12 設定項目のラベルが en/ja 両方でローカライズされている
- [ ] #13 設定窓が 1 枚の Form のままで、コードフォントと数値表示が別 Section として見分けられる幅になっている
<!-- AC:END -->
