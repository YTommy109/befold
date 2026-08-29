---
id: TASK-565
title: スクロール位置と表示モードの永続化をやめ、ウィンドウの生存期間だけの記憶にする
status: Done
assignee: []
created_date: '2026-08-29 00:51'
updated_date: '2026-08-29 09:57'
labels: []
dependencies: []
priority: high
type: task
ordinal: 820000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

ファイル単位の表示状態は `befold/App/PerFileStateStore.swift` が 5 つのストアに束ねて **UserDefaults へ永続化**している。このうち 2 つは永続化する価値が無い、あるいは害があると判断した。

### スクロール位置（`ScrollPositionStore`）— 害がある

- 保存しているのは `scrollTop` の**生ピクセル値**だけ（キー `"ViewerScrollPositions.rendered"` / `"ViewerScrollPositions.source"`、値は `Double`、`PathKeyedDictionary`）。
- 内容が変わったかどうかの検査を**一切していない**。読み出しは `ViewerDocumentPresenter.restoredScrollPosition(for:isSourceMode:)` の 1 箇所で、ここにもガードは無い。
- したがって「500px の位置で閉じる → 外部でファイルが縮む → 次に開くと元の文脈と無関係な 500px へ飛ぶ」が現状そのまま起きる。
- さらに `scrollTop` は内容だけでなく**ウィンドウ幅・倍率・フォント設定にも依存する**ため、内容が同一でも別のウィンドウ幅で開けば違う場所を指す。生ピクセル値の永続化は内容変化に限らず元々もろい。
- `ContentLoader` の `contentHash` は存在するが（`ViewerContentState` の「同一内容なら再描画をスキップ」用）、スクロール位置とは一緒に保存されていない。

### 表示モード（`DisplayModeStore`）— 価値が無い

- ソース表示で見たいファイルは実質プログラムのコードで、それは保存値と無関係に常にソース表示になる（`ViewerStore.effectiveDisplayMode` が `if displayMode == .rendered, showsCodeContent { return .source }`）。
- Markdown / CSV / TSV をソース表示で見たいケースは稀で、永続化して得られる利得が小さい。
- 既に「永続化されないライブなモード」の概念がある（CLI の `--source` / `--preview` によるこの起動限りの上書き。`DisplayModeStore.supportedDisplayMode(_:for:)` の doc コメントが、リネーム経路で保存値を読み直すとこのライブなモードが破棄されると警告している）。永続化をやめれば、この「保存値とライブな値の二重性」そのものが消える。

### 永続化を続けるもの

倍率（`ZoomStore`）・サイドバー開閉（`SidebarStateStore`）・ウィンドウフレーム（`WindowFrameStore`）は内容非依存のユーザーの意図なので現状のまま残す。

## このタスクを先にやる理由

TASK-564.3（PDF の表示位置をウィンドウの生存期間だけ記憶する）が同じ「永続化しない表示状態の置き場」を必要とする。先にここで置き場を作れば、PDF 側は相乗りするだけで済み、同種のものを二重に作らずに済む。TASK-564.1 をこのタスクに依存させてある。

## 論点（実装着手前に `/review-design` で詰める）

- **`DisplayModeStore` は 2 つの責務を持っている。** 永続化（`displayMode(for:)` / `setDisplayMode(_:for:)` / `migrateDisplayMode(from:to:)` / `migrateLegacySourceModesIfNeeded`）と、**降格規則** `supportedDisplayMode(_:for:)`。後者は FileType だけに依存する純粋関数で「降格の規則はこの 1 箇所だけに置く」と明記されており、**外してはならない**。永続化の半分だけを剥がし、降格規則の置き場をどこにするか（型名の変更か、別型への移動か）を決める。
- **セッション記憶のスコープ**: ウィンドウ単位か、アプリ単位（全ウィンドウ共有、アプリ終了で消える）か。既存ストアは全ウィンドウ共有の単一インスタンス（`PerFileStateStore` は `AppDelegate` が生成した 1 つを注入）なので、そこを揃えるか変えるかを決める。ADR 0002 の 3 分類（アプリの好み / 文書の状態 / 窓の状態）のどれに当たるかで判断すること。`GlobalDisplayBroadcaster` は表示モードも倍率も意図的に持たない設計（型の依存で担保）なので、そこへ足さないこと。
- **`PerFileStateStore` の形**: 永続 3 つとセッション 2 つが混ざる。「これは永続化しない」が読んで分かる形（名前・型・doc コメント）にすること。`migrate(from:to:)` はリネーム追従を 5 つまとめて行っているが、セッション記憶にも同じ追従が要るかを決める。
- **UserDefaults キーの廃止**: 消えるキーは `"ViewerScrollPositions.rendered"` / `"ViewerScrollPositions.source"` / `"ViewerDisplayModes"` と、旧キー `"ViewerSourceModes"` / `"SourceDiffEnabled"`（`migrateLegacySourceModesIfNeeded` が扱っているもの）。CLAUDE.md「UserDefaults キーの廃止・改名」の手順に従い、読み手が 0 になったキーを移行するかしないかを明示的に決め、いずれの経路でも `removeObject(forKey:)` で必ず消すこと。今回は移行先が無い（永続化そのものをやめる）ので「移行しない・削除する」になる見込みだが、判断として記録すること。
- **差分表示の再選択コスト**: 表示モードを永続化しないと、アプリ再起動後は毎回レンダリング表示から始まる。差分を見るために複数ファイルを渡り歩く使い方で `⌘3` を押し直す手間が増えないかを確認すること（同一セッション内はセッション記憶が効くため、影響は再起動をまたぐ場合に限られる）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 スクロール位置がアプリの再起動をまたいで復元されず、同一セッション内でファイルを行き来したときだけ復元される
- [x] #2 表示モードがアプリの再起動をまたいで復元されず、同一セッション内でファイルを行き来したときだけ復元される
- [x] #3 `DisplayModeStore.supportedDisplayMode(_:for:)` の降格規則が失われておらず、依然として 1 箇所にだけ存在する
- [x] #4 コード種別のファイルが従来どおりソース表示で開き、CLI の `--source` / `--preview` による上書きも従来どおり効く
- [x] #5 `"ViewerScrollPositions.rendered"` / `"ViewerScrollPositions.source"` / `"ViewerDisplayModes"` / `"ViewerSourceModes"` / `"SourceDiffEnabled"` のリテラルがコードから消え、既存ユーザーの defaults からも `removeObject(forKey:)` で削除される
- [x] #6 stale キーの削除を検証するユニットテストがある（旧値あり → 削除される / 旧値なし → 何も起きない）。分離した `UserDefaults`（`makeIsolatedDefaults(prefix:)`）上で書く
- [x] #7 スクロール位置と表示モードが UserDefaults へ書かれないことを検証するユニットテストがある（この判断が破れたら落ちるもの）
- [x] #8 倍率・サイドバー開閉・ウィンドウフレームの永続化は従来どおり動く
- [x] #9 ファイルのリネーム / 移動時の状態引き継ぎが、永続 3 つとセッション 2 つの双方で決めたとおりに動く
- [x] #10 `docs/dev/native-app-design.md` の表示状態の記述が更新されている
- [x] #11 `swift test` が通り、swiftlint の main とのベースライン差分がゼロである
- [x] #12 ViewerDocumentPresenter と WebViewCommandController の注入クロージャがそれぞれ 3 個以下になっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 方針

保存値の**読み書きの契機は一切変えない**（ADR 0002「文書の状態の規則」1 の構造と `ViewerWindowPresentationEntryPointTests` のトリップワイヤをそのまま生かす）。変えるのは保存値の**寿命と置き場**だけ。

## 手順

### 1. 揮発記憶の器を作る
- `BefoldApp/befold/App/PathKeyedTable.swift` を新設。`struct PathKeyedTable<Value>`（メモリ・値型）。`value(for:)` / `mutating setValue(_:for:)` / `mutating migrateValue(from:to:)`。キーは `url.normalizedPathKey`。
  **`PathKeyedDictionary` は触らない。** その上に載せ替えると「メモリと defaults のどちらが真実か」という新しい不変条件が生まれ、全窓共有の `PerFileStateStore` で他窓の書き込みが見えなくなる経路になる（/review-design M2）。重複する 3 行は受け入れる。
- `BefoldApp/befold/App/WindowPresentationMemory.swift` を新設。`@MainActor final class WindowPresentationMemory`。
  中身は rendered/source のスクロール位置 2 テーブルと表示モード 1 テーブル。
  API: `scrollPosition(for:mode:)` / `setScrollPosition(_:for:mode:)` / `displayMode(for:)` / `setDisplayMode(_:for:)` / `migrate(from:to:)`。
  **`UserDefaults` を引数にも stored property にも持たない**（永続化できないことを構造で担保）。
  doc に受け入れ条件を書く: 「永続化する状態（倍率・サイドバー・フレーム）はここに入れない。候補が出たら `PerFileStateStore` 側か判断してから足す」。
  `Store` 接尾辞を使わないのは、永続ストア群（`ZoomStore` 等）と命名で区別するため。

### 2. 所有関係（/review-design H3 に従う）
- `ViewerDocumentPresenter` が `WindowPresentationMemory` を stored property として所有する（窓ローカル per-path 記憶の前例 `sourceToggleReturn` と同じ層）。**注入クロージャは増やさない。**
- `ViewerWindowController` には stored property を足さない（グループ 894/900 行、stored property 21 個、プロトコル準拠 5 件。規約「ウィンドウコントローラを何でも置き場にしない」）。
- `WebViewCommandController.saveCurrentScrollPosition` から `perFileState.scrollPosition.setScrollPosition` を撤去し、`onScrollPositionSaved(position, url, mode)` の通知だけにする。書き手が presenter 1 箇所に集約される。倍率のための `perFileState` は残す。
- `ViewerDocumentPresenter.applySavedScrollPositionToLiveValue` が、ライブ値の更新に加えて揮発記憶への記録も行う。
- `ViewerWindowController+Renderer.renderer(_:didChangeScrollPosition:for:mode:)` は `documentPresenter.recordScrollPosition(...)` への薄い委譲に変える（行数は横ばい）。
- リネーム追従: `ViewerWindowController+FileNavigation.handleRename` から presenter 経由で `WindowPresentationMemory.migrate(from:to:)` を呼ぶ。`PerFileStateStore.migrate`（永続 3 つ）との 2 本立てになる。

### 3. 降格規則の移設（/review-design M3）
- `BefoldApp/befold/App/ViewerDisplayMode+FileType.swift` を新設し、`extension ViewerDisplayMode { func supported(for url: URL) -> ViewerDisplayMode }` を置く。
  ファイルを分けるのは依存の局所化のため（`ViewerDisplayMode.swift` 本体は `import Foundation` のまま保ち、`import BefoldKit` を拡張ファイルへ閉じる）。
- `DisplayModeStore.supportedDisplayMode` の doc にある「**降格の規則はこの 1 箇所だけに置く**」という単一情報源の宣言を、文言ごと移設先へ引き継ぐ。落とすと規則の単一性の記録が消える。
- 呼び出し元 2 箇所（`ViewerDocumentPresenter.applyCLIDisplayMode` / `ViewerWindowController+FileNavigation.handleRename`）を新 API へ向ける。

### 4. 旧ストアの削除と旧キーの掃除
- `ScrollPositionStore.swift` / `DisplayModeStore.swift` を削除。
- `PerFileStateStore` は zoom / sidebar / windowFrame の 3 つへ縮める。型 doc・`init` の Parameter doc・`migrate` の doc がいずれも 5 つを列挙しているので同時に直す（/review-design L1）。
- **`DisplayModeStore` を消すと `migrateLegacySourceModesIfNeeded` も消える**ため、旧キー削除の担い手が失われる。代わりに一度きりの掃除を `AppStores` に置き、次の 5 キーを `removeObject(forKey:)` する。
  `ViewerScrollPositions.rendered` / `ViewerScrollPositions.source` / `ViewerDisplayModes` / `ViewerSourceModes` / `SourceDiffEnabled`
  **移行はしない**（永続化そのものをやめるので移行先が無い）。この判断を Implementation Notes に記録する。
- `xcodegen generate` を実行（新規ファイル 3 つ、削除 2 つ）。

### 5. テスト
新規:
- `WindowPresentationMemory` の往復・モード独立・ファイル独立・rename 追従・**シンボリックリンク越しのパスキー正規化**（/review-design L2。永続側の `PerFileStateStoreSymlinkIntegrationTests` は揮発側を守らない）
- **揮発であることのトリップワイヤ**: 新しいインスタンスが空であること。加えて `WindowPresentationMemory(` の生成箇所をソース走査で固定し、`AppStores` 側で生成されて全窓共有へ falling back しないことを担保する（粒度を破ると落ちるもの／CLAUDE.md「決めたことには、破れたら落ちるものを付ける」）
- 旧 5 キーの掃除テスト（旧値あり → 削除される / 旧値なし → 何も起きない）。`makeIsolatedDefaults(prefix:)` 上で書く
- 降格規則のテストを `DisplayModeStoreTests` から移設先の名前へ付け替えて残す

書き換え:
- `ViewerWindowStateIndependenceTests.restoresStoredStateWhenReopening`（「閉じてから開き直すと、保存された倍率とスクロール位置から始まる」）→ **倍率は復元される / スクロール位置と表示モードは初期状態に戻る**へ。これが今回の仕様変更そのもの
- `ViewerWindowStateIndependenceTests.keepsLiveScrollPositionWhenStoredPositionChanges` → 窓ごとのストアになると他窓から書き換える経路が消えて空振りになる。倍率側（`keepsLiveZoomWhenStoredZoomChanges`）は共有・永続のまま残るのでそちらは維持し、スクロール位置は「2 窓が互いの位置を持たない」形へ書き換える
- `ViewerWindowControllerSourceModeTests` のうち事前に store へ仕込んで新窓を開く形（`openingFileDirectlyRestoresSavedSourceMode` 他）→ 同一窓内の往復へ
- `ViewerWindowControllerCLIOptionsTests.noSourceModeOverridePreservesSavedValue` / `sourceModeOverrideTakesPrecedenceOverSavedValue`
- `ViewerWindowManagerDisplayOverridesTests`（displayModeStore を使う）
- `PerFileStateStoreSymlinkIntegrationTests.scrollPositionResolvesSymlinkToSamePath` → 揮発側のテストへ移す
- `PerFileStateStoreTests` / `ViewerWindowControllerFixture`（`displayModeStore` の差し替え口を撤去）
- `ViewerContentViewStoreIsolationTests.forbiddenSymbols` から削除した型名を外す

削除: `ScrollPositionStoreTests` / `DisplayModeStoreTests`（降格規則の分は移設先へ）

### 6. ドキュメント
- `docs/adr/0002-presentation-state-and-capabilities.md`
  - 「3 分類」表の**文書の状態**の「持ち方」欄に、保存値の寿命が状態ごとに違うことを書く。例欄から `DisplayModeStore` / `ScrollPositionStore` を外す
  - 「引き受けた妥協」節に、スクロール位置と表示モードについてはこの妥協（再起動時に同一ファイルの複数窓が同じ値へ収束する）が消えたことを追記
  - 「実装状況」節を更新
- `docs/dev/native-app-design.md` のコンポーネント表 3 行と「表示仕様」節の 2 箇所

### 7. 検証
- `swift test`
- `/swiftlint-baseline` で main との差分ゼロ
- `scripts/check-type-group-size.sh`
- `scripts/check-doc-symbols.sh` / `markdownlint-cli2`

## 着手前に決めた事項

**注入クロージャ 4 個（規約の上限は 3 個）は今回返済しない。** `ViewerDocumentPresenter` / `WebViewCommandController` はいずれも既に 4 個で、`docs/dev/rules/product-code.md` の「クロージャバンドルが 3 つを超えたら delegate プロトコルを検討する」を超過している。ただし今回の変更が足すのは stored property であってクロージャではなく、悪化はさせない。返済は所有関係の組み替えを伴い TASK-565 のスコープを超えるため、別タスクとして起票する。

## 反映しなかったレビュー指摘

`sourceToggleReturn` を `WindowPresentationMemory` へ統合する案は**採らない**。キーが (パス) 単独で、`setDisplayMode` が捨てるという寿命規則を持ち、スクロール位置とは不変条件が違う。同居させると「何でも入る器」に近づく（/review-design Info の推奨と一致）。

## 追加: 注入クロージャ負債の返済（ユーザー判断により今回のタスク内で行う）

`ViewerDocumentPresenter` と `WebViewCommandController` はいずれも注入クロージャ 4 個で、
`docs/dev/rules/product-code.md` の「クロージャバンドルが 3 つを超えたら delegate プロトコルを
検討する」を超過している。両方の `currentURL` には「rename/switch で書き換わるため値を捕捉せず
コントローラ経由で参照する」というコメントが付いており、規定が「強く推奨」と名指しした
**再束縛回避のためのクロージャ**そのものになっている。

返済方針: `currentURL` を小さな共有参照型（例 `CurrentDocumentRef`）へ切り出し、
`ViewerWindowAssembler` が 1 個作って presenter と `WebViewCommandController` の両方へ渡す。
これで両方の子がクロージャ 3 個へ収まり、再束縛の必要も消える。
`ViewerWindowController` へのプロトコル準拠は増やさない（既に 5 件）。

この返済は「揮発記憶の導入で presenter の依存を触る」のと同じ箇所に当たるため、
同一タスク内で行う（CLAUDE.md「タスク中に発見したリファクタリング課題は次回に回さない」）。
ただし**コミットは分ける**（クロージャ返済 → 揮発化本体、の順）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装結果

コミットは 2 本に分けた（計画どおり）。

1. `cfcbbcaa` 注入クロージャ負債の返済。`CurrentDocumentRef`（`ViewerStore.currentURL` から
   導出するだけで値を複製しない共有参照）を新設し、`ViewerWindowController` が 1 個持って
   `ViewerDocumentPresenter` と `WebViewCommandController` の両方へ渡す。両者とも注入
   クロージャが 4 → 3 個になり、`ViewerWindowController.initialFileURL` と
   `ViewerWindowAssembler.makeWebViewCommands(fallbackURL:)` は不要になったので撤去。
2. `bb1b7b6f` 揮発化の本体。

## UserDefaults キーの判断（CLAUDE.md「UserDefaults キーの廃止・改名」）

**移行しない・削除する。** 永続化そのものをやめたので移行先が無い。対象 5 キーは
`AppStores.retiredDisplayStateKeys` に列挙し、`AppStores.init` が
`removeRetiredDisplayStateKeys(from: .standard)` で一括削除する。
`removeObject(forKey:)` は無条件に回るので、早期 return による取りこぼしの経路が無い。
旧キーリテラルは実測でプロダクト側 `AppStores.swift` の 5 件（= 一覧そのもの）と
テスト 10 件のみ（`grep -rn '"ViewerScrollPositions\|"ViewerDisplayModes"\|...'`）。

## 計画からの差分

- `WindowPresentationMemory` は `ViewerDocumentPresenter` の `private` ではなく
  internal な stored property にした。テストが記憶の中身を観測するため（doc に
  「本番コードからここを触らないこと」と明記）。
- `WebViewCommandController.saveCurrentScrollPosition` は永続化を落として通知だけに
  なったため、テスト `savesScrollPositionOnlyWhenAvailable` は
  `reportsScrollPositionOnlyWhenAvailable`（取得できたときだけ通知する）へ書き換えた。
- `applySavedScrollPositionToLiveValue` は**一致判定の前に**記憶する形にした。ここへ届くのは
  退場側（提示中とは限らない文書）の位置で、一致時だけ記憶すると切替の退場側が落ちるため。
- `ViewerWindowStateIndependenceTests.keepsLiveScrollPositionWhenStoredPositionChanges` は
  「2 窓が互いの位置を持たない」（`keepsScrollPositionPerWindow`）へ、
  `restoresStoredStateWhenReopening` は「倍率は保存値から・位置とモードは初期状態から」へ
  書き換えた。これが今回の仕様変更そのもの。

## 差分表示の再選択コストの確認（論点）

同一セッション内は窓の記憶が効くので、影響は**アプリ再起動をまたぐ場合だけ**。
再起動直後に差分を見たいときに `cmd+3` を 1 回押す必要が出るが、差分は
「いま何が変わったか」を見る一時的な読み方で、再起動をまたいで維持したい設定ではない
と判断した（永続化していた頃は、逆に「前回差分で閉じた」だけのファイルが差分で開いていた）。

## 検証

- `swift test`: 1731 tests / 277 suites、失敗は `SettingsViewSnapshotTests`
  「負の数の選択肢の見本が右端で揃っている」の 1 件のみ。**この失敗は既存**
  （`git diff origin/main -- SettingsViewSnapshotTests.swift SettingsView.swift` が空、
  単独実行でも同じく失敗）。
- swiftlint ベースライン差分ゼロ（main 54 件 / HEAD 54 件、真の新規・解消ともに空）。
- `scripts/check-type-group-size.sh` / `scripts/check-doc-symbols.sh` /
  `scripts/check-doc-citations.sh` / `markdownlint-cli2` いずれも OK。
  `.claude/CLAUDE.md` の「参考実装」は削除した `DisplayModeStore` を指していたので
  `AppStores.removeRetiredDisplayStateKeys`（移行しない側の前例）へ差し替えた。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
スクロール位置と表示モードを UserDefaults から外し、窓が所有する WindowPresentationMemory（UserDefaults を型の依存として持たない）へ移した。降格規則は ViewerDisplayMode.supported(for:) の 1 箇所へ移設し、旧 5 キーは移行せず AppStores が起動時に削除する。前段で CurrentDocumentRef を切り出し、ViewerDocumentPresenter と WebViewCommandController の注入クロージャを 4 → 3 個へ返済した。検証: swift test（既存の SettingsViewSnapshotTests 1 件を除き通過）、swiftlint ベースライン差分ゼロ、type-group-size / doc-symbols / doc-citations / markdownlint いずれも OK。
<!-- SECTION:FINAL_SUMMARY:END -->
