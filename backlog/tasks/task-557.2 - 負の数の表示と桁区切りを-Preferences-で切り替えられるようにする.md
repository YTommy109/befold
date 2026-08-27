---
id: TASK-557.2
title: 負の数の表示と桁区切りを Preferences で切り替えられるようにする
status: Done
assignee: []
created_date: '2026-08-27 04:20'
updated_date: '2026-08-27 06:51'
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
- [x] #1 桁区切りのオン/オフを Preferences から切り替えられ、既定はオン
- [x] #2 負の数の表示を 通常 / ▲ / 赤字 / ▲+赤字 から選べ、既定は 通常
- [x] #3 設定を変更すると、既に開いている窓の表示が再読み込みなしで変わる
- [x] #4 設定値が UserDefaults に永続化され、再起動後も復元される（未設定時は既定値）
- [x] #5 TASK-557.1 の第 1 段のみの列（コードとみなされた列）には ▲・赤字・桁区切りのいずれも適用されない
- [x] #6 設定項目のラベルが en/ja 両方でローカライズされている
- [x] #7 設定窓が 1 枚の Form のままで、コードフォントと数値表示が別 Section として見分けられる幅になっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー（実装前に 1 回）の結論

- 表示設定が JS へ届く経路は 2 本（窓の初期ロード注入 / 設定変更のブロードキャスト）。**両方に配線する**。片方だけだと「桁区切りを切った状態で新しい窓を開くと復活する」。
- コードフォントは CSS 変数を書くだけで再描画不要だが、数値表示は HTML 文字列が変わるので**再描画が要る**。view-options.ts は「状態を持つだけで再描画しない」という逆の約束を明記しているので相乗りさせず、_mmdInitCsvNumberFormat() が値を読んで _mmdRerenderCurrent() まで行う。
- Preference は AppStores が 1 つ持つ app-global。ViewerWindowManager.init の新引数に**デフォルト値を付けない**（codeFontPreference の既定値付き引数は TASK-319 と同型の穴。既存分は別途起票）。
- 赤字はダークモードで読める色が要る。--csv-negative-fg を light/dark で分ける。
- QuickLook 拡張には Preferences が届かない（ViewerRenderer.makeWebView の既定値のまま）。既定値＝桁区切りオン・通常表記で固定。コードフォントと同じ扱いの意図した縮退として記録する。
- FeatureGate は使わない（557.1 が既にゲート無しで入っているため）。

## 手順

1. BefoldKit に `public enum CsvNegativeStyle: String, CaseIterable, Sendable`（plain / triangle / red / triangleRed）を置く。Swift 側と JS 側で文字列を二重管理しないため、ここを唯一の情報源にする。
2. `befold/App/CsvNumberFormatPreference.swift`: @MainActor final class。UserDefaults キー `CsvNumberGrouping`(Bool, 既定 true) / `CsvNegativeStyle`(String, 既定 plain)、didSet 書き戻し、`init(defaults: UserDefaults = .standard)`。CodeFontPreference に倣う。AppStores へ束ねる。
3. ViewerBridge: `csvNumberGroupingScript(_:)` / `csvNegativeStyleScript(_:)` / `applyCsvNumberFormatScript(grouping:negativeStyle:)` を追加し、PlainFunction に `initCsvNumberFormat = "_mmdInitCsvNumberFormat"` を足す（契約テストが実在を検証する）。
4. 初期ロード注入: ViewerWebViewFactory.Options に 2 フィールドを足し、ViewerRenderer.makeWebView → ViewerWebView → ViewerContentView → ViewerWindowAssembler まで通す。
5. ブロードキャスト: GlobalDisplayBroadcaster.applyCsvNumberFormatToAllWindows() → ViewerWindowController.applyCsvNumberFormatFromPreference() → WebViewCommandController.applyCsvNumberFormat(...) → WebViewDocumentRenderer（DocumentRendering プロトコルにも追加）。
6. viewer-src: csv-number-format.ts（app-global の状態 + _mmdInitCsvNumberFormat）を新設し、csv-html.ts のセル組み立てが参照する。viewer-globals.d.ts に `_mmdCsvGrouping` / `_mmdCsvNegativeStyle` を宣言。負の数は grouped 列にのみ適用（AC #5）。
7. 設定画面: CodeFontSettingsView → SettingsView へ型・ファイルを改名し、Section「数値表示」を「プレビュー」の後ろに足す（プレビューはコードフォントの見本なのでフォント Section の直後に残す）。.frame(width: 360) を 460 へ広げる。xcodegen generate。
8. ローカライズ: settings.number.* を en/ja 両方。キー順のソートし直しはしない。
9. テスト: CsvNumberFormatPreferenceTests（既定値 / 永続化 / 不正値）、ViewerBridgeTests（スクリプト生成）、WebViewCommandControllerTests（スパイ）、jest（桁区切りオフ・▲・赤字・コード列に適用されないこと）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- 負の数の表記の enum は `BefoldKit/CsvNegativeStyle.swift` に置いた。Swift(設定・ブリッジ)と JS(受理リスト)の両方に現れる文字列なので、片側だけ足しても実行時に「未知の値」として既定へ倒れて黙って効かなくなる。**この型を唯一の情報源にし、一致は契約テストで機械的に突き合わせる**。
- `CsvNumberFormatPreference` は app-global。`ViewerWindowManager`/`ViewerWindowController` の init 引数に**既定値を付けていない**（隣の `codeFontPreference` には既定値が付いており、これは TASK-319 と同型の穴。既存分は本タスクでは触らず別途起票する）。
- 桁区切りは `bool(forKey:)` で読まない。未設定でも false が返り「既定はオン」が成立しないため、`object(forKey:) as? Bool` で未設定と明示オフを区別する。
- 反映経路は 2 本とも配線した。窓の初期ロード注入（`ViewerWebViewFactory.Options` → `userScriptSources`）と設定変更のブロードキャスト（`GlobalDisplayBroadcaster.applyCsvNumberFormatToAllWindows`）。片方だけだと「桁区切りを切った状態で新しい窓を開くと復活する」。
- JS 側の入口 `_mmdInitCsvNumberFormat` は `render.ts` に置いた。`csv-number-format.ts` から `render.js` を import すると render → csv-html → csv-number-format → render の循環になり `check:viewer-cycles` が落ちるため。状態だけを持つモジュールと、再描画を伴う入口を分けてある。
- `view-options.ts` へ相乗りさせなかった。あちらは「状態を持つだけで再描画しない（Swift が直後に render を送る）」という**逆の約束**で揃えてあり、混ぜるとどちらの規則で読むか分からなくなる。

## swiftlint の新規違反 3 件を分割で解消

閾値は緩めず、CLAUDE.md の方針どおり分割した。

- `ViewerBridge.swift` が 401 行（上限 400）→ CSV のスクリプト生成を `ViewerBridge+CsvNumberFormat.swift` へ切り出し。Swift の private はファイルスコープなので `assignGlobalScript` / `defaultingFallback` を internal へ上げ、「BefoldKit の外からは使わないこと」を doc コメントで補った。
- `ViewerBridgeTests` が type_body_length 超過 → `ViewerBridgeCsvNumberFormatTests.swift` へ分離。
- `ViewerWindowController.init` が 51 行（上限 50）→ 最初の文書を開くまでの 4 文（sidebar.attach / refreshFileList / wireStoreCallbacks / store.openFile）を `ViewerWindowAssembler.openInitialDocument(for:at:adopting:)` へ寄せた。順序に意味がある一続きなので、行数調整ではなく凝集の改善になっている。

## 意図した縮退

**QuickLook 拡張には設定が届かない。** `ViewerRenderer.makeWebView` の引数は既定値（grouping = true / .plain）で、appex は常にその見た目で描く。コードフォント（family/points が nil 固定）と同じ扱い。

## 検証

- `swift test`: 1712 件全通し（ベースライン 1702 → +10）
- `npx jest`: 630 件全通し（新規の数値表示テスト 10 件を含む）
- **担保が実際に効くことを実測した**（テストを通すだけでは何も検証していないため）
  - JS の受理リストから `triangleRed` を落としてバンドルを作り直すと、契約テスト `CsvNegativeStyle の rawValue が viewer-bundle.js の受理リストと一致する` が落ちる。なお当初の `source.contains(rawValue)` 版は 800KB のバンドル内の無関係な一致（"plain" 等）で通ってしまうため、配列リテラルを取り出して集合ごと比較する形へ書き換えた
  - `.frame(width: 460)` を 360 へ戻すと `設定窓は Section を見分けられる幅を持つ` が落ちる
- swiftlint: main とのベースライン差分**ゼロ**（main 54 件 / HEAD 54 件、真の新規なし）
- `npm run lint`（--type-aware）/ `format:check` / `typecheck:viewer` / `check:viewer-cycles`: ゼロ件
- l10n: 208 キーに翻訳漏れ・state 異常・プレースホルダ不一致なし（新規 settings.number.* 7 件は en/ja 両方）
- `docs/dev/native-app-design.md` に設定の項と GlobalDisplayBroadcaster の説明を追随済み

## pre-commit の型グループ検査で 2 件の閾値超過（追加対応）

swiftlint とは別に `scripts/check-type-group-size.sh` が走り、次を報告した。**extension へ切っても合算値は減らない**という CLAUDE.md の警告どおりの結果で、最初の分割は swiftlint の file_length を満たしただけだった。

- `ViewerBridge` グループ 416 行（閾値 400、main は 377）→ `ViewerBridge+CsvNumberFormat.swift` を**兄弟型 `ViewerCsvBridge`** へ作り直した。`ViewerBridgeMessage` / `ViewerDiffBridge` と同じ並びで、これは責務の分離になっている。結果 390 行。
- `ViewerWindowController` グループ 908 行（恒久例外の上限 900、main は 897）→ 上限を上げず、`applyCodeFontFromPreference` / `applyCsvNumberFormatFromPreference` の**中継メソッドを撤去**して設定の読み取りを `GlobalDisplayBroadcaster` 側へ寄せた。broadcaster は「アプリの好みを全窓へ配る」型なので、設定を読むのはそちらが本来の持ち場。窓ごとに読み手が増えるのも止まる。結果 890 行（main より 7 行少ない）。
- 併せて `ViewerBridgeContractTests` が type_body_length を超えたため、CSV の契約テストも `ViewerBridgeCsvNumberFormatTests` へ寄せた（スクリプト生成と受理リストの一致を 1 か所で見る形になった）。

再検証: swift test 1712 件全通し / swiftlint ベースライン差分ゼロ（main 54・HEAD 54）/ 型グループ検査 exit 0 / jest 630 件全通し。

## 追記: 負の数の設定をラジオボタンにした（ユーザー指摘）

ポップアップ（既定の Picker）だと選択中の 1 つしか見えず、▲ と赤字がどう出るかを比べられない。`.pickerStyle(.radioGroup)` にして 4 つの表示例を同時に見せる形へ変えた。

- 選択肢のラベルは「名前 + その設定での見え方の例」。赤字を選ぶ 2 つは**見本そのものを赤で描く**ので、選ばなくても結果が分かる。
- 見本は表示中の CSV とは無関係の**固定の見本文字列**（`-1,234` / `▲1,234`）。実際の整形は viewer 側が行うので、Swift 側で同じ規則を実装し直してはいない。
- ローカライズのキーからは例を外した（例は別に描くので二重になる）。en は Normal / Triangle / Red / Triangle and red、ja は 通常 / ▲ 表記 / 赤字 / ▲ + 赤字。

## 見た目の検証方法（実測で 1 度失敗している）

- **ImageRenderer では描けない。** `Form` + `.formStyle(.grouped)` は AppKit 実装で、`ImageRenderer(content:).nsImage` は**真っ白な画像**を返した（実際に撮って目視で確認）。
- 実ウィンドウへ載せて `NSView.cacheDisplay(in:to:)` で撮る形に変えたら描けた。画面キャプチャではないので TCC の許可が要らず、非対話セッションでも回せる。ヘッドレスではウィンドウが 0 高のまま（bounds が `(0,0,1,0)`）で撮れなかったため、`fittingSize` を測って明示的に与えている。
- 撮った PNG を目視し、ラジオボタン 4 つが同時に見えること・赤字の見本が実際に赤で出ることを確認した。
- その上で機械的にも測れるようにした（`SettingsViewSnapshotTests`）。ビットマップから直接ピクセルを見て、赤いピクセルが存在すること・描画結果が真っ白でないことをアサートする。`foregroundColor(.red)` を `.primary` へ変えると赤の検査が落ちることを実測済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CSV/TSV の数値表示（桁区切りの有無と負の数の表記）を app-global の Preferences から切り替えられるようにした。負の数の表記は BefoldKit の CsvNegativeStyle を唯一の情報源とし、Swift と JS の受理リストの一致を契約テストで突き合わせる。反映は窓の初期ロード注入と全窓ブロードキャストの 2 本とも配線し、viewer 側は CSS 変数では表せないため現在の文書を描き直す。設定画面は CodeFontSettingsView を SettingsView へ改名して Section を足し、幅を 460 へ広げた。検証は swift test 1712 件・jest 630 件の全通しに加え、契約テストと幅の回帰テストが変更を戻すと実際に落ちることを実測。swiftlint はベースライン差分ゼロ（新規 3 件は閾値を緩めず分割で解消）。
<!-- SECTION:FINAL_SUMMARY:END -->
