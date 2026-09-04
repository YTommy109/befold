# サイドバーのスライドモード

<!-- constrained-by ../../adr/0002-presentation-state-and-capabilities.md -->
<!-- derived-from ./2026-08-13-sidebar-header-controls-design.md -->

> **これは 2026-09-04 時点の設計スナップショットです。**
> 現在の仕様は [`docs/dev/native-app-design.md`](../../dev/native-app-design.md)
> が単一の情報源。この文書は当時の意図と検討経緯を残すためのもので、
> 現在の実装と食い違っていることがある。着手前に必ずコードで裏を取ること。

## 目的（TASK-585）

プレゼンテーション中に、**フォーカスをサイドバーに残したままカーソルキーで
ファイルを送りたい**。本文を全画面に近い幅で見せながら、次の資料へ移る操作は
キーだけで済ませたい、という要求。

現在の `ViewerSplitViewController` は `minimumThickness = 200` /
`maximumThickness = 360` を `init` で固定しており、サイドバーを「アイコンの列」
まで細くできない。畳んでしまうとフォーカスの移り先が無くなるので、
畳むことでは代替できない。

## 決めたこと

**明示的なモードにする。** 幅に応じてヘッダーの密度を段階的に変える案
（full / compact / minimal）を先に検討したが取り下げた。レスポンシブにすると、
畳んだ絞り込みが効いていることを伝える手掛かり・フィルター入力欄の扱い・
閾値の基準幅など、幅の連続変化に伴う分岐が増える。プレゼンという一時的な行為に
対しては、幅を固定した 1 つのモードのほうが状態が少ない。

| 項目 | 決定 |
| --- | --- |
| 状態のスコープ | 窓ごと。永続化しない（再起動で必ず OFF） |
| 進入・解除 | 表示メニューのトグル / ヘッダーのアイコンを押す（esc は用意しない） |
| 行の見え方 | 選択行のハイライトのみ。ファイル名は本文側で分かるものとする |
| サイドバー幅 | アイコン幅に固定（ドラッグ不可） |
| ヘッダー | スライドモードを示すアイコン 1 つに置き換える |
| 併せて変更 | `maximumThickness` 360 → 480。`minimumThickness` は 200 のまま |

esc を解除手段から外したのは、esc の受け手が SwiftUI の `onKeyPress`・AppKit の
`cancelOperation`・WKWebView 内の JS の 3 層に散っていて中央の処理が無く、
first responder がどの面にあるかで効いたり効かなかったりするため。

## 設計

### 状態の置き場

`isSlideMode` を `FileListModel` の stored property に置く。同じ型の
`filterText` / `isFilterActive` が「窓ごと・永続化しない」という同じ性質で
既に載っており、`@Observable` なのでヘッダーがそのまま観測できる。

**真値はここ 1 つだけにする。** `ViewerSplitViewController` 側に真偽値を
持たせず、幅だけを持たせる。二重に持つと幅と表示が食い違う形が作れてしまう。

窓ごとの状態なので、メニューの配線は `AppDelegate.sidebarChange(for:)` の表
（`SidebarDisplayDefaults` へ永続化される系統）ではなく、
`ViewerWindowController` の `validateMenuItem` と `ViewerMenuValidator` の
系統に載せる。

### autosave の汚染を止める

`splitView.autosaveName` が設定されているため、AppKit は任意のタイミングで
ディバイダー位置を `NSSplitView Subview Frames ViewerSplitView` へ書き出す。
スライドモード中の細幅が焼き込まれると、`viewWillAppear` の「記憶があれば
上書きしない」規則がそれを固定化し、次に開いた窓のサイドバーが細いままになる。

進入時に `autosaveName` を nil にして書き出しを止め、退出時に幅を戻してから
再設定する。この形なら、スライドモードのままアプリを終了しても細幅は
書き出されない。`autosaveName` を触る箇所は `ViewerSplitViewController` の
private メソッド 1 つに閉じ、外から設定できないようにする。

進入前の幅は同コントローラが覚え、退出時に `setPosition` で戻す。
`minimumThickness` を実行中に変える前例はリポジトリに無い（`setPosition` の
呼び出しも `viewWillAppear` の 1 箇所だけ）ので、**min / max を先に変えてから
`setPosition` する**順序を doc コメントで固定する。逆順だと clamp される。

未確認: `autosaveName` を再設定したとき AppKit が保存済みフレームを読み直して
適用するか。適用しても値は進入前の幅と一致するので実害は無いと見ているが、
実機で確認する。

### 幅の値

`SidebarSlideMetrics` に定数として置く。行の幾何は
`SidebarRowIndent.rowHorizontalPadding` 8×2 + `SidebarRowIndent.disclosureWidth` 12
+ 行の `HStack` spacing 2 + アイコン 16 = 54pt で、これに `List`（NSTableView
裏打ち）のインセットが乗る。実機で実測して確定し、実測値と算出根拠を
タスクの Implementation Notes に残す。

### 開閉状態を汚さないための制約

`setSidebarCollapsed` は `toggleSidebar` を再利用しており、
`onCollapsedChange` から `SidebarStateStore.recordToggle` が走って
「最後にユーザーが操作した開閉状態」を書き換える。スライドモードが自動で
開閉すると、ユーザーが操作していない開閉が保存され、以後の新規ウィンドウの
初期値を汚す。

**自動で開閉しないことで、この経路そのものを作らない。**

- サイドバーが畳まれている間はメニュー項目を無効にする。`ViewerMenuValidator`
  は ⌘← の有効判定で `isSidebarCollapsed` を既に読んでいるので、同じ判定を
  再利用する
- スライドモード中にサイドバーを畳んだら、スライドモードを解除する

### ヘッダー

`isSlideMode` が true のとき、`SidebarHeaderView` は `BaseDirectoryIndicator` も
操作行もフィルター欄も出さず、スライドモードを示すアイコン 1 つだけを描く。
そのアイコンがそのまま解除ボタンになる。

進入時に `closeFilter()` を呼ぶ。入力欄が消えるのに絞り込みが残ると、細い一覧が
「なぜこれだけなのか」分からなくなるため。`showChangedFilesOnly` /
`showHiddenFiles` はメニュー側にチェック状態が出るので、そのまま維持する。

### フォーカス

進入直後に `FileListModel.tableFocuser` の `focus()` を呼ぶ。これが目的そのもの。
この口はテーブルが現れるまで要求を保留する仕組みを既に持っているので、
幅の変更と同一ランループで走っても成立する。

## テスト

| 対象 | 測り方 |
| --- | --- |
| 幅の幾何 | `SidebarSlideMetricsTests`（新規） |
| メニューのチェック状態と有効判定 | `ViewerMenuValidatorTests`（既存を拡張）。畳んでいるとき無効になること |
| 進入でフィルターが閉じること | 新規のユニットテスト |
| サイドバーを畳むと解除されること | 新規のユニットテスト |
| autosave が汚れないこと | 手動確認。手順と `NSSplitView Subview Frames ViewerSplitView` の実測値を Notes に残す |
| 幅とヘッダーの外観 | 手動確認（GUI 層は自動テスト対象外） |

## 決めたことを守らせるもの

- 真値が 1 つであること — `ViewerSplitViewController` に真偽値を持たせない
- 開閉状態を汚さないこと — 自動開閉の経路を作らず、畳んでいる間は無効にする
  （`ViewerMenuValidator` のテストが固定する）
- autosave を止めること — `autosaveName` を触る箇所を private メソッド 1 つに閉じる

## 範囲外

- キーボードショートカットの割り当て（今回は付けない）
- スライドモード中のファイル名表示（ハイライトのみと決めた）
- 幅に応じた段階的なヘッダー密度（この設計で取り下げた）
