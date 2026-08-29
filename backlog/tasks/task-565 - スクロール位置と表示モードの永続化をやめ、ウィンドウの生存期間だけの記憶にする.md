---
id: TASK-565
title: スクロール位置と表示モードの永続化をやめ、ウィンドウの生存期間だけの記憶にする
status: To Do
assignee: []
created_date: '2026-08-29 00:51'
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
- [ ] #1 スクロール位置がアプリの再起動をまたいで復元されず、同一セッション内でファイルを行き来したときだけ復元される
- [ ] #2 表示モードがアプリの再起動をまたいで復元されず、同一セッション内でファイルを行き来したときだけ復元される
- [ ] #3 `DisplayModeStore.supportedDisplayMode(_:for:)` の降格規則が失われておらず、依然として 1 箇所にだけ存在する
- [ ] #4 コード種別のファイルが従来どおりソース表示で開き、CLI の `--source` / `--preview` による上書きも従来どおり効く
- [ ] #5 `"ViewerScrollPositions.rendered"` / `"ViewerScrollPositions.source"` / `"ViewerDisplayModes"` / `"ViewerSourceModes"` / `"SourceDiffEnabled"` のリテラルがコードから消え、既存ユーザーの defaults からも `removeObject(forKey:)` で削除される
- [ ] #6 stale キーの削除を検証するユニットテストがある（旧値あり → 削除される / 旧値なし → 何も起きない）。分離した `UserDefaults`（`makeIsolatedDefaults(prefix:)`）上で書く
- [ ] #7 スクロール位置と表示モードが UserDefaults へ書かれないことを検証するユニットテストがある（この判断が破れたら落ちるもの）
- [ ] #8 倍率・サイドバー開閉・ウィンドウフレームの永続化は従来どおり動く
- [ ] #9 ファイルのリネーム / 移動時の状態引き継ぎが、永続 3 つとセッション 2 つの双方で決めたとおりに動く
- [ ] #10 `docs/dev/native-app-design.md` の表示状態の記述が更新されている
- [ ] #11 `swift test` が通り、swiftlint の main とのベースライン差分がゼロである
<!-- AC:END -->
